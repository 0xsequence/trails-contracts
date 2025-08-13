// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TrailsTokenSweeper
 * @author Shun Kakinoki
 * @dev This contract can be used to sweep native tokens or ERC20 tokens from this contract to a specified address.
 */
contract TrailsTokenSweeper {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------

    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NativeTransferFailed();
    error NotDelegateCall();

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
     * @notice Sweeps the entire balance of a given token owned by the caller to the specified recipient.
     * @dev For ERC20 tokens, the caller must approve this contract first. For native tokens,
     *      this function forwards the msg.value sent with the call.
     * @param _token The address of the token to sweep. Use address(0) for the native token.
     * @param _recipient The address to send the swept tokens to.
     */
    function sweep(address _token, address _recipient) external payable onlyDelegatecall {
        if (_token == address(0)) {
            uint256 amount = address(this).balance;
            (bool success,) = payable(_recipient).call{value: amount}("");
            if (!success) revert NativeTransferFailed();
            emit Sweep(_token, _recipient, amount);
        } else {
            uint256 amount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(_recipient, amount);
            emit Sweep(_token, _recipient, amount);
        }
    }
}
