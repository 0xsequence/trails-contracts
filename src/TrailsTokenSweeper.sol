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
            uint256 amount = address(this).balance;
            (bool success,) = payable(_recipient).call{value: amount}("");
            if (!success) revert NativeTransferFailed();
            emit Sweep(_token, _recipient, amount);
        } else {
            IERC20 erc20 = IERC20(_token);
            SafeERC20.forceApprove(erc20, SELF, type(uint256).max);
            uint256 amount = erc20.balanceOf(address(this));
            SafeERC20.safeTransfer(erc20, _recipient, amount);
            emit Sweep(_token, _recipient, amount);
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

        revert InvalidDelegatedSelector(selector);
    }
}
