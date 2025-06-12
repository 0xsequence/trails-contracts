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
    using SafeERC20 for IERC20;

    address payable public immutable recipient;

    /**
     * @dev Sets the recipient address.
     */
    constructor(address payable _recipient) {
        require(_recipient != address(0), "AnypayTokenSweeper: recipient cannot be the zero address");
        recipient = _recipient;
    }

    /**
     * @dev Allows the contract to receive Ether.
     */
    receive() external payable {}

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

    /**
     * @notice Sweeps the entire balance of a given token to the immutable recipient address.
     * @dev Anyone can call this function.
     * @param _token The address of the token to sweep. Use address(0) for the native token.
     */
    function sweep(address _token) external {
        uint256 balance = getBalance(_token);
        _sweep(_token, balance);
    }

    /**
     * @notice Sweeps a specified amount of a given token to the immutable recipient address.
     * @dev Anyone can call this function.
     * @param _token The address of the token to sweep. Use address(0) for the native token.
     * @param _amount The amount of the token to sweep.
     */
    function sweep(address _token, uint256 _amount) external {
        _sweep(_token, _amount);
    }

    function _sweep(address _token, uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }

        uint256 balance = getBalance(_token);
        require(balance >= _amount, "AnypayTokenSweeper: insufficient balance");

        if (_token == address(0)) {
            (bool success,) = recipient.call{value: _amount}("");
            require(success, "AnypayTokenSweeper: Native token transfer failed");
        } else {
            IERC20(_token).safeTransfer(recipient, _amount);
        }
    }
}
