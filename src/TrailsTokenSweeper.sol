// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDelegatedExtension} from "wallet-contracts-v3/modules/interfaces/IDelegatedExtension.sol";

/**
 * @title TrailsTokenSweeper
 * @author Shun Kakinoki
 * @dev This contract can be used to sweep native tokens or ERC20 tokens from this contract to a specified address.
 */
contract TrailsTokenSweeper is IDelegatedExtension {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------

    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NativeTransferFailed();
    error NotDelegateCall();
    error InvalidDelegatedSelector(bytes4 selector);

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Refund(address indexed token, address indexed recipient, uint256 amount);
    event Sweep(address indexed token, address indexed recipient, uint256 amount);

    // -------------------------------------------------------------------------
    // Constants / Modifiers
    // -------------------------------------------------------------------------

    address private immutable SELF = address(this);

    modifier onlyDelegatecall() {
        if (address(this) == SELF) revert NotDelegateCall();
        _;
    }

    // -------------------------------------------------------------------------
    // View Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Gets the balance of a given token.
     * @param _token The address of the token. Use address(0) for the native token.
     * @return The balance of the token.
     */
    function getBalance(address _token) public view returns (uint256) {
        if (_token == address(0)) {
            return msg.sender.balance;
        } else {
            return IERC20(_token).balanceOf(msg.sender);
        }
    }

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

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

    // -------------------------------------------------------------------------
    // External Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Approves the sweeper if ERC20, then sweeps the entire balance to recipient.
     * @dev Approval is set for `SELF` (the sweeper contract) on the wallet (delegatecall context).
     *      For native tokens, approval is skipped and the native balance is swept.
     * @param _token The address of the token to sweep. Use address(0) for the native token.
     * @param _recipient The address to send the swept tokens to.
     */
    function sweep(address _token, address _recipient) public payable onlyDelegatecall {
        if (_token == address(0)) {
            uint256 amount = _nativeBalance();
            _transferNative(_recipient, amount);
            emit Sweep(_token, _recipient, amount);
        } else {
            _ensureERC20Approval(_token);
            uint256 amount = _erc20Balance(_token);
            _transferERC20(_token, _recipient, amount);
            emit Sweep(_token, _recipient, amount);
        }
    }

    /**
     * @notice Refunds up to `_refundAmount` to `_refundRecipient`, then sweeps any remaining balance to `_sweepRecipient`.
     * @dev For ERC20 tokens, sets infinite approval to `SELF` in delegatecall context for compatibility, then transfers.
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
            _transferNative(_refundRecipient, _refundAmount);
            emit Refund(_token, _refundRecipient, _refundAmount);

            uint256 remaining = _nativeBalance();
            _transferNative(_sweepRecipient, remaining);
            emit Sweep(_token, _sweepRecipient, remaining);
        } else {
            uint256 balance = _erc20Balance(_token);
            _ensureERC20Approval(_token, balance);

            _transferERC20(_token, _refundRecipient, _refundAmount);
            emit Refund(_token, _refundRecipient, _refundAmount);

            uint256 remaining = _erc20Balance(_token);
            _transferERC20(_token, _sweepRecipient, remaining);
            emit Sweep(_token, _sweepRecipient, remaining);
        }
    }

    // -------------------------------------------------------------------------
    // Sequence Delegated Extension Entry Point
    // -------------------------------------------------------------------------

    /**
     * @notice Entry point for Sequence delegatecall routing.
     * @dev The wallet module delegatecalls this function with the original call data in `_data`.
     *      We decode the selector and dispatch to the corresponding function in this contract.
     *      Execution context is that of the wallet (delegatecall), which is required for sweeping.
     */
    function handleSequenceDelegateCall(
        bytes32, /* _opHash */
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

        revert InvalidDelegatedSelector(selector);
    }
}
