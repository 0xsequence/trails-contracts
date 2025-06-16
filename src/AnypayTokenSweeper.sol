// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AnypayTokenSweeper
 * @author Shun Kakinoki
 * @dev This contract can be used to sweep native tokens or ERC20 tokens from this contract to a specified address.
 * The recipient address is set at deployment and is immutable.
 */
contract AnypayTokenSweeper {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------

    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @dev The address to send the swept tokens to.
    address payable public immutable recipient;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @dev Sets the recipient address.
     */
    constructor(address payable _recipient) {
        require(_recipient != address(0), "AnypayTokenSweeper: recipient cannot be the zero address");
        recipient = _recipient;
    }

    // -------------------------------------------------------------------------
    // Receive Function
    // -------------------------------------------------------------------------

    /**
     * @dev Allows the contract to receive Ether.
     */
    receive() external payable {}

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
            return address(this).balance;
        } else {
            return IERC20(_token).balanceOf(address(this));
        }
    }

    // -------------------------------------------------------------------------
    // External Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Sweeps the entire balance of a given token to the immutable recipient address.
     * @dev Anyone can call this function.
     * @param _token The address of the token to sweep. Use address(0) for the native token.
     */
    function sweep(address _token) external {
        uint256 balance = getBalance(_token);
        
        if (balance == 0) {
            return;
        }

        if (_token == address(0)) {
            (bool success, ) = recipient.call{value: balance}("");
            require(success, "AnypayTokenSweeper: Native token transfer failed");
        } else {
            IERC20(_token).safeTransfer(recipient, balance);
        }
    }
} 
