// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDelegatedExtension} from "wallet-contracts-v3/modules/interfaces/IDelegatedExtension.sol";
import {Tstorish} from "tstorish/Tstorish.sol";
import {DelegatecallGuard} from "./guards/DelegatecallGuard.sol";
import {IMulticall3} from "./interfaces/IMulticall3.sol";
import {ITrailsRouter} from "./interfaces/ITrailsRouter.sol";
import {TrailsSentinelLib} from "./libraries/TrailsSentinelLib.sol";

/// @title TrailsRouter
/// @author Miguel Mota, Shun Kakinoki
/// @notice Consolidated router for Trails operations including multicall routing, balance injection, and token sweeping
/// @dev Must be delegatecalled via the Sequence delegated extension module to access wallet storage/balances.
contract TrailsRouter is IDelegatedExtension, ITrailsRouter, DelegatecallGuard, Tstorish {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Immutable Variables
    // -------------------------------------------------------------------------

    address public immutable MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NativeTransferFailed();
    error InvalidDelegatedSelector(bytes4 selector);
    error InvalidFunctionSelector(bytes4 selector);
    error AllowFailureMustBeFalse(uint256 callIndex);
    error SuccessSentinelNotSet();
    error NoEthSent();
    error NoTokensToPull();
    error InsufficientEth(uint256 required, uint256 received);
    error NoTokensToSweep();
    error NoEthAvailable();
    error AmountOffsetOutOfBounds();
    error PlaceholderMismatch();
    error TargetCallFailed(bytes revertData);

    // -------------------------------------------------------------------------
    // Receive ETH
    // -------------------------------------------------------------------------

    /// @notice Allow direct native token transfers when contract is used standalone.
    receive() external payable {}

    // -------------------------------------------------------------------------
    // Multicall3 Router Functions
    // -------------------------------------------------------------------------

    /// @inheritdoc ITrailsRouter
    function execute(bytes calldata data) public payable returns (IMulticall3.Result[] memory returnResults) {
        _validateRouterCall(data);
        (bool success, bytes memory returnData) = MULTICALL3.delegatecall(data);
        if (!success) revert TargetCallFailed(returnData);
        return abi.decode(returnData, (IMulticall3.Result[]));
    }

    /// @inheritdoc ITrailsRouter
    function pullAndExecute(address token, bytes calldata data)
        public
        payable
        returns (IMulticall3.Result[] memory returnResults)
    {
        uint256 amount;
        if (token == address(0)) {
            if (msg.value == 0) revert NoEthSent();
            amount = msg.value;
        } else {
            amount = _getBalance(token, msg.sender);
            if (amount == 0) revert NoTokensToPull();
        }

        return pullAmountAndExecute(token, amount, data);
    }

    /// @inheritdoc ITrailsRouter
    function pullAmountAndExecute(address token, uint256 amount, bytes calldata data)
        public
        payable
        returns (IMulticall3.Result[] memory returnResults)
    {
        _validateRouterCall(data);
        if (token == address(0)) {
            if (msg.value < amount) revert InsufficientEth(amount, msg.value);
        } else {
            _safeTransferFrom(token, msg.sender, address(this), amount);
        }

        (bool success, bytes memory returnData) = MULTICALL3.delegatecall(data);
        if (!success) revert TargetCallFailed(returnData);
        return abi.decode(returnData, (IMulticall3.Result[]));
    }

    // -------------------------------------------------------------------------
    // Balance Injection Functions
    // -------------------------------------------------------------------------

    /// @inheritdoc ITrailsRouter
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
            if (callerBalance == 0) revert NoEthSent();
        } else {
            callerBalance = _getBalance(token, msg.sender);
            if (callerBalance == 0) revert NoTokensToSweep();
            _safeTransferFrom(token, msg.sender, address(this), callerBalance);
        }

        _injectAndExecuteCall(token, target, callData, amountOffset, placeholder, callerBalance);
    }

    /// @inheritdoc ITrailsRouter
    function injectAndCall(
        address token,
        address target,
        bytes calldata callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) public payable {
        uint256 callerBalance = _getSelfBalance(token);
        if (callerBalance == 0) {
            if (token == address(0)) {
                revert NoEthAvailable();
            } else {
                revert NoTokensToSweep();
            }
        }

        _injectAndExecuteCall(token, target, callData, amountOffset, placeholder, callerBalance);
    }

    // -------------------------------------------------------------------------
    // Token Sweeper Functions
    // -------------------------------------------------------------------------

    /// @inheritdoc ITrailsRouter
    function sweep(address _token, address _recipient) public payable onlyDelegatecall {
        uint256 amount = _getSelfBalance(_token);
        if (amount > 0) {
            if (_token == address(0)) {
                _transferNative(_recipient, amount);
            } else {
                _transferERC20(_token, _recipient, amount);
            }
            emit Sweep(_token, _recipient, amount);
        }
    }

    /// @inheritdoc ITrailsRouter
    function refundAndSweep(address _token, address _refundRecipient, uint256 _refundAmount, address _sweepRecipient)
        public
        payable
        onlyDelegatecall
    {
        uint256 current = _getSelfBalance(_token);

        uint256 actualRefund = _refundAmount > current ? current : _refundAmount;
        if (actualRefund != _refundAmount) {
            emit ActualRefund(_token, _refundRecipient, _refundAmount, actualRefund);
        }
        if (actualRefund > 0) {
            if (_token == address(0)) {
                _transferNative(_refundRecipient, actualRefund);
            } else {
                _transferERC20(_token, _refundRecipient, actualRefund);
            }
            emit Refund(_token, _refundRecipient, actualRefund);
        }

        uint256 remaining = _getSelfBalance(_token);
        if (remaining > 0) {
            if (_token == address(0)) {
                _transferNative(_sweepRecipient, remaining);
            } else {
                _transferERC20(_token, _sweepRecipient, remaining);
            }
            emit Sweep(_token, _sweepRecipient, remaining);
        }
        emit RefundAndSweep(_token, _refundRecipient, _refundAmount, _sweepRecipient, actualRefund, remaining);
    }

    /// @inheritdoc ITrailsRouter
    function validateOpHashAndSweep(bytes32 opHash, address _token, address _recipient)
        public
        payable
        onlyDelegatecall
    {
        uint256 slot = TrailsSentinelLib.successSlot(opHash);
        if (_getTstorish(slot) != TrailsSentinelLib.SUCCESS_VALUE) {
            revert SuccessSentinelNotSet();
        }
        sweep(_token, _recipient);
    }

    // -------------------------------------------------------------------------
    // Sequence Delegated Extension Entry Point
    // -------------------------------------------------------------------------

    /// @inheritdoc IDelegatedExtension
    function handleSequenceDelegateCall(
        bytes32 _opHash,
        uint256, /* _startingGas */
        uint256, /* _index */
        uint256, /* _numCalls */
        uint256, /* _space */
        bytes calldata _data
    )
        external
        override(IDelegatedExtension, ITrailsRouter)
        onlyDelegatecall
    {
        bytes4 selector;
        if (_data.length >= 4) {
            selector = bytes4(_data[0:4]);
        }

        // Balance Injection selectors
        if (selector == this.injectAndCall.selector) {
            (address token, address target, bytes memory callData, uint256 amountOffset, bytes32 placeholder) =
                abi.decode(_data[4:], (address, address, bytes, uint256, bytes32));
            _injectAndCallDelegated(token, target, callData, amountOffset, placeholder);
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

    /// forge-lint: disable-next-line(mixed-case-function)
    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        IERC20 erc20 = IERC20(token);
        SafeERC20.safeTransferFrom(erc20, from, to, amount);
    }

    /// forge-lint: disable-next-line(mixed-case-function)
    function _transferNative(address _to, uint256 _amount) internal {
        (bool success,) = payable(_to).call{value: _amount}("");
        if (!success) revert NativeTransferFailed();
    }

    /// forge-lint: disable-next-line(mixed-case-function)
    function _transferERC20(address _token, address _to, uint256 _amount) internal {
        IERC20 erc20 = IERC20(_token);
        SafeERC20.safeTransfer(erc20, _to, _amount);
    }

    /// forge-lint: disable-next-line(mixed-case-function)
    function _getBalance(address token, address account) internal view returns (uint256) {
        return token == address(0) ? account.balance : IERC20(token).balanceOf(account);
    }

    /// forge-lint: disable-next-line(mixed-case-function)
    function _getSelfBalance(address token) internal view returns (uint256) {
        return _getBalance(token, address(this));
    }

    /// forge-lint: disable-next-line(mixed-case-function)
    function _nativeBalance() internal view returns (uint256) {
        return address(this).balance;
    }

    /// forge-lint: disable-next-line(mixed-case-function)
    function _erc20Balance(address _token) internal view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    /// forge-lint: disable-next-line(mixed-case-function)
    function _erc20BalanceOf(address _token, address _account) internal view returns (uint256) {
        return IERC20(_token).balanceOf(_account);
    }

    /// forge-lint: disable-next-line(mixed-case-function)
    function _injectAndCallDelegated(
        address token,
        address target,
        bytes memory callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) internal {
        uint256 callerBalance = _getSelfBalance(token);
        if (callerBalance == 0) {
            if (token == address(0)) {
                revert NoEthAvailable();
            } else {
                revert NoTokensToSweep();
            }
        }

        _injectAndExecuteCall(token, target, callData, amountOffset, placeholder, callerBalance);
    }

    /// forge-lint: disable-next-line(mixed-case-function)
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
            if (callData.length < amountOffset + 32) revert AmountOffsetOutOfBounds();

            bytes32 found;
            assembly {
                found := mload(add(add(callData, 32), amountOffset))
            }
            if (found != placeholder) revert PlaceholderMismatch();

            assembly {
                mstore(add(add(callData, 32), amountOffset), callerBalance)
            }
        }

        // Execute call based on token type
        if (token == address(0)) {
            (bool success, bytes memory result) = target.call{value: callerBalance}(callData);
            emit BalanceInjectorCall(token, target, placeholder, callerBalance, amountOffset, success, result);
            if (!success) revert TargetCallFailed(result);
        } else {
            IERC20 erc20 = IERC20(token);
            SafeERC20.forceApprove(erc20, target, callerBalance);

            (bool success, bytes memory result) = target.call(callData);
            emit BalanceInjectorCall(token, target, placeholder, callerBalance, amountOffset, success, result);
            if (!success) revert TargetCallFailed(result);
        }
    }

    /// forge-lint: disable-next-line(mixed-case-function)
    function _validateRouterCall(bytes memory callData) internal pure {
        // Extract function selector
        if (callData.length < 4) revert InvalidFunctionSelector(bytes4(0));

        bytes4 selector;
        assembly {
            selector := mload(add(callData, 32))
        }

        // Only allow `aggregate3Value` calls (0x174dea71)
        if (selector != 0x174dea71) {
            revert InvalidFunctionSelector(selector);
        }

        // Decode and validate the Call3Value[] array to ensure allowFailure=false for all calls
        IMulticall3.Call3Value[] memory calls = abi.decode(_sliceCallData(callData, 4), (IMulticall3.Call3Value[]));

        // Iterate through all calls and verify allowFailure is false
        for (uint256 i = 0; i < calls.length; i++) {
            if (calls[i].allowFailure) {
                revert AllowFailureMustBeFalse(i);
            }
        }
    }

    /// forge-lint: disable-next-line(mixed-case-function)
    function _sliceCallData(bytes memory data, uint256 start) internal pure returns (bytes memory) {
        bytes memory result = new bytes(data.length - start);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }
}
