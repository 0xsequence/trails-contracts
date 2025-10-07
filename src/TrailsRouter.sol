// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDelegatedExtension} from "wallet-contracts-v3/modules/interfaces/IDelegatedExtension.sol";
import {Storage} from "wallet-contracts-v3/modules/Storage.sol";
import {TrailsSentinelLib} from "./libraries/TrailsSentinelLib.sol";

// -----------------------------------------------------------------------------
// Interfaces
// -----------------------------------------------------------------------------

interface IMulticall3 {
    struct Call3 {
        address target;
        bool allowFailure;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    function aggregate3(Call3[] calldata calls) external payable returns (Result[] memory returnData);
}

/// @title TrailsRouter
/// @author Miguel Mota, Shun Kakinoki
/// @notice Consolidated router for Trails operations including multicall routing, balance injection, and token sweeping
contract TrailsRouter is IDelegatedExtension {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Immutable Variables
    // -------------------------------------------------------------------------

    address public immutable multicall3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address private immutable SELF = address(this);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NativeTransferFailed();
    error NotDelegateCall();
    error InvalidDelegatedSelector(bytes4 selector);
    error SuccessSentinelNotSet();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event BalanceInjectorCall(
        address indexed token,
        address indexed target,
        bytes32 placeholder,
        uint256 amountReplaced,
        uint256 amountOffset,
        bool success,
        bytes result
    );
    event Refund(address indexed token, address indexed recipient, uint256 amount);
    event Sweep(address indexed token, address indexed recipient, uint256 amount);
    event RefundAndSweep(
        address indexed token,
        address indexed refundRecipient,
        uint256 refundAmount,
        address indexed sweepRecipient,
        uint256 actualRefund,
        uint256 remaining
    );
    event ActualRefund(address indexed token, address indexed recipient, uint256 expected, uint256 actual);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyDelegatecall() {
        if (address(this) == SELF) revert NotDelegateCall();
        _;
    }

    // -------------------------------------------------------------------------
    // Multicall3 Router Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Aggregates multiple calls in a single transaction.
     * @dev Delegates to Multicall3 to preserve msg.sender context.
     * @param data The data to execute.
     * @return returnResults The result of the execution.
     */
    function execute(bytes calldata data) public payable returns (IMulticall3.Result[] memory returnResults) {
        (bool success, bytes memory returnData) = multicall3.delegatecall(data);
        require(success, "TrailsRouter: call failed");
        return abi.decode(returnData, (IMulticall3.Result[]));
    }

    /**
     * @notice Pull ERC20 from msg.sender, then delegatecall into Multicall3.
     * @dev Requires prior approval to this router.
     * @param token The ERC20 token to pull, or address(0) for ETH.
     * @param data The calldata for Multicall3.
     * @return returnResults The result of the execution.
     */
    function pullAndExecute(address token, bytes calldata data)
        public
        payable
        returns (IMulticall3.Result[] memory returnResults)
    {
        if (token != address(0)) {
            uint256 amount = _erc20BalanceOf(token, msg.sender);
            _safeTransferFrom(token, msg.sender, address(this), amount);
        }

        (bool success, bytes memory returnData) = multicall3.delegatecall(data);
        require(success, "TrailsRouter: pullAndExecute failed");
        return abi.decode(returnData, (IMulticall3.Result[]));
    }

    /**
     * @notice Pull specific amount of ERC20 from msg.sender, then delegatecall into Multicall3.
     * @dev Requires prior approval to this router.
     * @param token The ERC20 token to pull, or address(0) for ETH.
     * @param amount The amount to pull.
     * @param data The calldata for Multicall3.
     * @return returnResults The result of the execution.
     */
    function pullAmountAndExecute(address token, uint256 amount, bytes calldata data)
        public
        payable
        returns (IMulticall3.Result[] memory returnResults)
    {
        if (token != address(0)) {
            _safeTransferFrom(token, msg.sender, address(this), amount);
        }

        (bool success, bytes memory returnData) = multicall3.delegatecall(data);
        require(success, "TrailsRouter: pullAmountAndExecute failed");
        return abi.decode(returnData, (IMulticall3.Result[]));
    }

    // -------------------------------------------------------------------------
    // Balance Injection Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Sweeps tokens from msg.sender and calls target with modified calldata.
     * @dev For regular calls (not delegatecall). Transfers tokens from msg.sender to this contract first.
     * @param token The ERC-20 token to sweep, or address(0) for ETH.
     * @param target The address to call with modified calldata.
     * @param callData The original calldata (must include a 32-byte placeholder).
     * @param amountOffset The byte offset in calldata where the placeholder is located.
     * @param placeholder The 32-byte placeholder that will be replaced with balance.
     */
    function injectSweepAndCall(
        address token,
        address target,
        bytes calldata callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) external payable {
        uint256 callerBalance;

        if (token == address(0)) {
            callerBalance = msg.value;
            require(callerBalance > 0, "No ETH sent");
        } else {
            callerBalance = _erc20BalanceOf(token, msg.sender);
            require(callerBalance > 0, "No tokens to sweep");
            _safeTransferFrom(token, msg.sender, address(this), callerBalance);
        }

        _injectAndExecuteCall(token, target, callData, amountOffset, placeholder, callerBalance);
    }

    /**
     * @notice Injects balance and calls target (for delegatecall context).
     * @dev For delegatecalls from Sequence wallets. Reads balance from address(this).
     * @param token The ERC-20 token to sweep, or address(0) for ETH.
     * @param target The address to call with modified calldata.
     * @param callData The original calldata (must include a 32-byte placeholder).
     * @param amountOffset The byte offset in calldata where the placeholder is located.
     * @param placeholder The 32-byte placeholder that will be replaced with balance.
     */
    function injectAndCall(
        address token,
        address target,
        bytes calldata callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) external payable {
        _injectAndCall(token, target, callData, amountOffset, placeholder);
    }

    function _injectAndCall(
        address token,
        address target,
        bytes memory callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) internal {
        uint256 callerBalance;

        if (token == address(0)) {
            callerBalance = _nativeBalance();
            require(callerBalance > 0, "No ETH available in contract");
        } else {
            callerBalance = _erc20Balance(token);
            require(callerBalance > 0, "No tokens to sweep");
        }

        _injectAndExecuteCall(token, target, callData, amountOffset, placeholder, callerBalance);
    }

    function _injectAndExecuteCall(
        address token,
        address target,
        bytes memory callData,
        uint256 amountOffset,
        bytes32 placeholder,
        uint256 callerBalance
    ) internal {
        // Replace placeholder with actual balance if needed
        bool shouldReplace = (amountOffset != 0 || placeholder != bytes32(0));

        if (shouldReplace) {
            require(callData.length >= amountOffset + 32, "amountOffset out of bounds");

            bytes32 found;
            assembly {
                found := mload(add(add(callData, 32), amountOffset))
            }
            require(found == placeholder, "Placeholder mismatch");

            assembly {
                mstore(add(add(callData, 32), amountOffset), callerBalance)
            }
        }

        // Execute call based on token type
        if (token == address(0)) {
            (bool success, bytes memory result) = target.call{value: callerBalance}(callData);
            emit BalanceInjectorCall(token, target, placeholder, callerBalance, amountOffset, success, result);
            require(success, string(result));
        } else {
            IERC20 erc20 = IERC20(token);
            SafeERC20.forceApprove(erc20, target, callerBalance);

            (bool success, bytes memory result) = target.call(callData);
            emit BalanceInjectorCall(token, target, placeholder, callerBalance, amountOffset, success, result);
            require(success, string(result));
        }
    }

    // -------------------------------------------------------------------------
    // Token Sweeper Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Approves the sweeper if ERC20, then sweeps the entire balance to recipient.
     * @dev For delegatecall context. Approval is set for `SELF` on the wallet.
     * @param _token The address of the token to sweep. Use address(0) for the native token.
     * @param _recipient The address to send the swept tokens to.
     */
    function sweep(address _token, address _recipient) public payable onlyDelegatecall {
        if (_token == address(0)) {
            uint256 amount = _nativeBalance();
            _transferNative(_recipient, amount);
            emit Sweep(_token, _recipient, amount);
        } else {
            uint256 amount = _erc20Balance(_token);
            _ensureERC20Approval(_token, amount);
            _transferERC20(_token, _recipient, amount);
            emit Sweep(_token, _recipient, amount);
        }
    }

    /**
     * @notice Refunds up to `_refundAmount` to `_refundRecipient`, then sweeps any remaining balance to `_sweepRecipient`.
     * @dev For delegatecall context.
     * @param _token The token address to operate on. Use address(0) for native.
     * @param _refundRecipient Address receiving the refund portion.
     * @param _refundAmount Maximum amount to refund.
     * @param _sweepRecipient Address receiving the remaining balance.
     */
    function refundAndSweep(address _token, address _refundRecipient, uint256 _refundAmount, address _sweepRecipient)
        public
        payable
        onlyDelegatecall
    {
        if (_token == address(0)) {
            uint256 current = _nativeBalance();

            uint256 actualRefund = _refundAmount > current ? current : _refundAmount;
            if (actualRefund != _refundAmount) {
                emit ActualRefund(_token, _refundRecipient, _refundAmount, actualRefund);
            }
            if (actualRefund > 0) {
                _transferNative(_refundRecipient, actualRefund);
                emit Refund(_token, _refundRecipient, actualRefund);
            }

            uint256 remaining = _nativeBalance();
            if (remaining > 0) {
                _transferNative(_sweepRecipient, remaining);
                emit Sweep(_token, _sweepRecipient, remaining);
            }
            emit RefundAndSweep(_token, _refundRecipient, _refundAmount, _sweepRecipient, actualRefund, remaining);
        } else {
            uint256 balance = _erc20Balance(_token);
            _ensureERC20Approval(_token, balance);

            uint256 actualRefund = _refundAmount > balance ? balance : _refundAmount;
            if (actualRefund != _refundAmount) {
                emit ActualRefund(_token, _refundRecipient, _refundAmount, actualRefund);
            }
            if (actualRefund > 0) {
                _transferERC20(_token, _refundRecipient, actualRefund);
                emit Refund(_token, _refundRecipient, actualRefund);
            }

            uint256 remaining = _erc20Balance(_token);
            if (remaining > 0) {
                _transferERC20(_token, _sweepRecipient, remaining);
                emit Sweep(_token, _sweepRecipient, remaining);
            }
            emit RefundAndSweep(_token, _refundRecipient, _refundAmount, _sweepRecipient, actualRefund, remaining);
        }
    }

    /**
     * @notice Validates that the success sentinel for an opHash is set, then sweeps tokens.
     * @dev For delegatecall context. Used to ensure prior operation succeeded.
     * @param opHash The operation hash to validate.
     * @param _token The token to sweep.
     * @param _recipient The recipient of the sweep.
     */
    function validateOpHashAndSweep(bytes32 opHash, address _token, address _recipient)
        public
        payable
        onlyDelegatecall
    {
        bytes32 slot = TrailsSentinelLib.successSlot(opHash);
        if (Storage.readBytes32(slot) != TrailsSentinelLib.SUCCESS_VALUE) {
            revert SuccessSentinelNotSet();
        }
        sweep(_token, _recipient);
    }

    // -------------------------------------------------------------------------
    // Sequence Delegated Extension Entry Point
    // -------------------------------------------------------------------------

    /**
     * @notice Entry point for Sequence delegatecall routing.
     * @dev The wallet module delegatecalls this function with the original call data in `_data`.
     *      We decode the selector and dispatch to the corresponding function in this contract.
     */
    function handleSequenceDelegateCall(
        bytes32 _opHash,
        uint256, /* _startingGas */
        uint256, /* _index */
        uint256, /* _numCalls */
        uint256, /* _space */
        bytes calldata _data
    ) external override onlyDelegatecall {
        bytes4 selector;
        if (_data.length >= 4) {
            selector = bytes4(_data[0:4]);
        }

        // Balance Injection selectors
        if (selector == this.injectAndCall.selector) {
            (address token, address target, bytes memory callData, uint256 amountOffset, bytes32 placeholder) =
                abi.decode(_data[4:], (address, address, bytes, uint256, bytes32));
            _injectAndCall(token, target, callData, amountOffset, placeholder);
            return;
        }

        // Token Sweeper selectors
        if (selector == this.sweep.selector) {
            (address token, address recipient) = abi.decode(_data[4:], (address, address));
            sweep(token, recipient);
            return;
        }

        if (selector == this.refundAndSweep.selector) {
            (address token, address refundRecipient, uint256 refundAmount, address sweepRecipient) =
                abi.decode(_data[4:], (address, address, uint256, address));
            refundAndSweep(token, refundRecipient, refundAmount, sweepRecipient);
            return;
        }

        if (selector == this.validateOpHashAndSweep.selector) {
            (, address token, address recipient) = abi.decode(_data[4:], (bytes32, address, address));
            validateOpHashAndSweep(_opHash, token, recipient);
            return;
        }

        revert InvalidDelegatedSelector(selector);
    }

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        IERC20 erc20 = IERC20(token);
        SafeERC20.safeTransferFrom(erc20, from, to, amount);
    }

    function _ensureERC20Approval(address _token, uint256 _amount) internal {
        IERC20 erc20 = IERC20(_token);
        SafeERC20.forceApprove(erc20, SELF, _amount);
    }

    function _transferNative(address _to, uint256 _amount) internal {
        (bool success,) = payable(_to).call{value: _amount}("");
        if (!success) revert NativeTransferFailed();
    }

    function _transferERC20(address _token, address _to, uint256 _amount) internal {
        IERC20 erc20 = IERC20(_token);
        SafeERC20.safeTransfer(erc20, _to, _amount);
    }

    function _nativeBalance() internal view returns (uint256) {
        return address(this).balance;
    }

    function _erc20Balance(address _token) internal view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function _erc20BalanceOf(address _token, address _account) internal view returns (uint256) {
        return IERC20(_token).balanceOf(_account);
    }

    // -------------------------------------------------------------------------
    // Receive ETH
    // -------------------------------------------------------------------------

    receive() external payable {}
}
