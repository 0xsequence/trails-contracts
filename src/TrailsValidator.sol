// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

// From: https://github.com/0xsequence/wallet-contracts/blob/db6789c3f8ad774dc55253f0599e0f2f0833f76a/contracts/modules/utils/RequireUtils.sol

/**
 * @title TrailsValidator
 * @notice Validation utilities for Trails intent transactions using msg.sender
 * @dev All functions use msg.sender to check the caller's balances/allowances,
 *      which allows these calls to be included in counterfactual address derivation
 *      without creating circular dependencies.
 */
contract TrailsValidator {
    /**
     * @notice Validates that a given expiration hasn't expired
     * @dev Used as an optional transaction on a Sequence batch, to create expirable transactions.
     * @param _expiration Expiration timestamp to check
     */
    function requireNonExpired(uint256 _expiration) external view {
        require(block.timestamp < _expiration, "TrailsValidator#requireNonExpired: EXPIRED");
    }

    /**
     * @notice Validates that msg.sender has a minimum ERC20 token balance
     * @param _token ERC20 token address
     * @param _minBalance Minimum required balance
     */
    function requireMinERC20Balance(address _token, uint256 _minBalance) external view {
        uint256 balance = IERC20(_token).balanceOf(msg.sender);
        require(balance >= _minBalance, "TrailsValidator#requireMinERC20Balance: BALANCE_TOO_LOW");
    }

    /**
     * @notice Validates that msg.sender has a minimum native token balance
     * @param _minBalance Minimum required balance
     */
    function requireMinNativeBalance(uint256 _minBalance) external view {
        require(msg.sender.balance >= _minBalance, "TrailsValidator#requireMinNativeBalance: BALANCE_TOO_LOW");
    }

    /**
     * @notice Validates that msg.sender has a minimum ERC20 allowance for a spender
     * @param _token ERC20 token address
     * @param _spender Address allowed to spend the tokens
     * @param _minAllowance Minimum required allowance
     */
    function requireMinERC20Allowance(address _token, address _spender, uint256 _minAllowance) external view {
        uint256 allowance = IERC20(_token).allowance(msg.sender, _spender);
        require(allowance >= _minAllowance, "TrailsValidator#requireMinERC20Allowance: ALLOWANCE_TOO_LOW");
    }

    /**
     * @notice Validates that msg.sender owns a specific ERC721 token
     * @param _token ERC721 token address
     * @param _tokenId Token ID to check for ownership
     */
    function requireERC721Ownership(address _token, uint256 _tokenId) external view {
        address owner = IERC721(_token).ownerOf(_tokenId);
        require(owner == msg.sender, "TrailsValidator#requireERC721Ownership: NOT_OWNER");
    }

    /**
     * @notice Validates that an ERC721 token owned by msg.sender is approved for a specific spender
     * @param _token ERC721 token address
     * @param _spender Address that should have approval
     * @param _tokenId Token ID to check for approval
     */
    function requireERC721Approval(address _token, address _spender, uint256 _tokenId) external view {
        address approved = IERC721(_token).getApproved(_tokenId);
        require(
            approved == _spender || IERC721(_token).isApprovedForAll(msg.sender, _spender),
            "TrailsValidator#requireERC721Approval: NOT_APPROVED"
        );
    }

    /**
     * @notice Validates that msg.sender has a minimum balance of an ERC1155 token
     * @param _token ERC1155 token address
     * @param _tokenId Token ID to check
     * @param _minBalance Minimum required balance
     */
    function requireMinERC1155Balance(address _token, uint256 _tokenId, uint256 _minBalance) external view {
        uint256 balance = IERC1155(_token).balanceOf(msg.sender, _tokenId);
        require(balance >= _minBalance, "TrailsValidator#requireMinERC1155Balance: BALANCE_TOO_LOW");
    }

    /**
     * @notice Validates that an ERC1155 token is approved for a specific operator by msg.sender
     * @param _token ERC1155 token address
     * @param _operator Address that should have operator approval
     */
    function requireERC1155Approval(address _token, address _operator) external view {
        bool isApproved = IERC1155(_token).isApprovedForAll(msg.sender, _operator);
        require(isApproved, "TrailsValidator#requireERC1155Approval: NOT_APPROVED");
    }
}
