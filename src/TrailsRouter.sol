// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDelegatedExtension} from "wallet-contracts-v3/modules/interfaces/IDelegatedExtension.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {Tstorish} from "tstorish/Tstorish.sol";
import {DelegatecallGuard} from "./guards/DelegatecallGuard.sol";
import {ITrailsRouter} from "./interfaces/ITrailsRouter.sol";
import {TrailsSentinelLib} from "./libraries/TrailsSentinelLib.sol";

/// @notice Guest module interface for forwarding CallsPayload
interface IGuest {
    /// @notice Fallback function that accepts CallsPayload encoded data
    fallback() external payable;
}

/// @title TrailsRouter
/// @author Miguel Mota, Shun Kakinoki
/// @notice Consolidated router for Trails operations including call routing, balance injection, and token sweeping
/// @dev Must be delegatecalled via the Sequence delegated extension module to access wallet storage/balances.
///      Uses Sequence V3 CallsPayload format for batch call execution.
///      Forwards CallsPayload to Guest module for execution (similar to how Multicall3 was used).
contract TrailsRouter is IDelegatedExtension, ITrailsRouter, DelegatecallGuard, Tstorish {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Immutable Variables
    // -------------------------------------------------------------------------

    /// @notice Address of the Sequence V3 Guest module for forwarding CallsPayload
    /// @dev Guest module address is deterministic via CREATE2 deployment
    address public immutable GUEST_MODULE = 0x0000000000000000000000000000000000000001;


    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NativeTransferFailed();
    error InvalidDelegatedSelector(bytes4 selector);
    error InvalidPayloadFormat();
    error CallExecutionFailed(uint256 callIndex, bytes revertData);
    error SuccessSentinelNotSet();
    error NoValueAvailable();
    error NoTokensToPull();
    error IncorrectValue(uint256 required, uint256 received);
    error NoTokensToSweep();
    error AmountOffsetOutOfBounds();
    error PlaceholderMismatch();
    error TargetCallFailed(bytes revertData);

    // -------------------------------------------------------------------------
    // Receive ETH
    // -------------------------------------------------------------------------

    /// @notice Allow direct native token transfers when contract is used standalone.
    receive() external payable {}

    // -------------------------------------------------------------------------
    // Router Functions
    // -------------------------------------------------------------------------

    /// @inheritdoc ITrailsRouter
    /// @dev Accepts Sequence V3 CallsPayload format. Forwards to Guest module for execution.
    ///      Guest module doesn't return results, matching its fallback function behavior.
    function execute(bytes calldata data) public payable {
        // Validate payload is transaction kind
        Payload.Decoded memory decoded = Payload.fromPackedCalls(data);
        if (decoded.kind != Payload.KIND_TRANSACTIONS) {
            revert InvalidPayloadFormat();
        }

        // Forward CallsPayload to Guest module (similar to how Multicall3 was used)
        // Guest module's fallback accepts CallsPayload encoded data and doesn't return anything
        (bool success, bytes memory returnData) = GUEST_MODULE.call{value: msg.value}(data);
        if (!success) {
            revert TargetCallFailed(returnData);
        }
        // Guest module execution completed successfully - no return value
    }

    /// @inheritdoc ITrailsRouter
    function pullAndExecute(address token, bytes calldata data) public payable {
        uint256 amount;
        if (token == address(0)) {
            if (msg.value == 0) revert NoValueAvailable();
            amount = msg.value;
        } else {
            amount = _getBalance(token, msg.sender);
            if (amount == 0) revert NoTokensToPull();
        }

        pullAmountAndExecute(token, amount, data);
    }

    /// @inheritdoc ITrailsRouter
    /// @dev Accepts Sequence V3 CallsPayload format. Forwards to Guest module for execution.
    ///      Guest module doesn't return results, matching its fallback function behavior.
    function pullAmountAndExecute(address token, uint256 amount, bytes calldata data) public payable {
        // Pull tokens first
        if (token == address(0)) {
            if (msg.value != amount) revert IncorrectValue(amount, msg.value);
        } else {
            if (msg.value != 0) revert IncorrectValue(0, msg.value);
            _safeTransferFrom(token, msg.sender, address(this), amount);
        }

        // Validate payload is transaction kind
        Payload.Decoded memory decoded = Payload.fromPackedCalls(data);
        if (decoded.kind != Payload.KIND_TRANSACTIONS) {
            revert InvalidPayloadFormat();
        }

        // Forward CallsPayload to Guest module (similar to how Multicall3 was used)
        // Guest module's fallback accepts CallsPayload encoded data and doesn't return anything
        (bool success, bytes memory returnData) = GUEST_MODULE.call{value: msg.value}(data);
        if (!success) {
            revert TargetCallFailed(returnData);
        }
        // Guest module execution completed successfully - no return value

        // Sweep remaining balance back to msg.sender to prevent dust from EXACT_OUTPUT swaps getting stuck.
        // We sweep the full balance (not tracking initial) since TrailsRouter is stateless by design.
        uint256 remaining = _getSelfBalance(token);
        if (remaining > 0) {
            if (token == address(0)) {
                _transferNative(msg.sender, remaining);
            } else {
                _transferERC20(token, msg.sender, remaining);
            }
            emit Sweep(token, msg.sender, remaining);
        }
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
            if (callerBalance == 0) revert NoValueAvailable();
        } else {
            if (msg.value != 0) revert IncorrectValue(0, msg.value);
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
        if (token == address(0) && msg.value != 0) {
            revert IncorrectValue(0, msg.value);
        }

        uint256 callerBalance = _getSelfBalance(token);
        if (callerBalance == 0) {
            if (token == address(0)) {
                revert NoValueAvailable();
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
                revert NoValueAvailable();
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

}
