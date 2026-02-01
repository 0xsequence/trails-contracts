// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

/// @title RequireUtils
/// @notice A set of small, composable precondition checks intended to be called from an intent's call batch.
/// @dev Each function reverts with a custom error (cheap + structured) on failure.
contract RequireUtils {
  /// @notice The transaction is expired.
  error Expired(uint256 expiration, uint256 timestamp);
  /// @notice The ERC20 balance is too low.
  error ERC20BalanceTooLow(address token, address owner, uint256 balance, uint256 minBalance);
  /// @notice The ERC20 allowance is too low.
  error ERC20AllowanceTooLow(address token, address owner, address spender, uint256 allowance, uint256 minAllowance);
  /// @notice The ERC721 is not owned.
  error ERC721NotOwner(address token, uint256 tokenId, address owner, address requiredOwner);
  /// @notice The ERC721 is not approved.
  error ERC721NotApproved(address token, uint256 tokenId, address owner, address spender);
  /// @notice The ERC1155 balance is too low.
  error ERC1155BalanceTooLow(address token, address owner, uint256 tokenId, uint256 balance, uint256 minBalance);
  /// @notice The length mismatch.
  error LengthMismatch(uint256 a, uint256 b);
  /// @notice The ERC1155 batch balance is too low.
  error ERC1155BatchBalanceTooLow(uint256 index, uint256 balance, uint256 minBalance);
  /// @notice The ERC1155 is not approved.
  error ERC1155NotApproved(address token, address owner, address operator);
  /// @notice The native balance is too low.
  error NativeBalanceTooLow(address owner, uint256 balance, uint256 minBalance);

  function _requireMinBalance(address owner, uint256 minBalance) private view {
    uint256 balance = owner.balance;
    if (balance < minBalance) {
      revert NativeBalanceTooLow(owner, balance, minBalance);
    }
  }

  function _requireMinERC20Balance(address token, address owner, uint256 minBalance) private view {
    uint256 balance = IERC20(token).balanceOf(owner);
    if (balance < minBalance) {
      revert ERC20BalanceTooLow(token, owner, balance, minBalance);
    }
  }

  function _requireMinERC20Allowance(address token, address owner, address spender, uint256 minAllowance) private view {
    uint256 allowance = IERC20(token).allowance(owner, spender);
    if (allowance < minAllowance) {
      revert ERC20AllowanceTooLow(token, owner, spender, allowance, minAllowance);
    }
  }

  function _requireERC721Owner(address token, address requiredOwner, uint256 tokenId) private view {
    address owner = IERC721(token).ownerOf(tokenId);
    if (owner != requiredOwner) {
      revert ERC721NotOwner(token, tokenId, owner, requiredOwner);
    }
  }

  function _requireERC721Approval(address token, address owner, address spender, uint256 tokenId) private view {
    address approved = IERC721(token).getApproved(tokenId);
    if (approved != spender && !IERC721(token).isApprovedForAll(owner, spender)) {
      revert ERC721NotApproved(token, tokenId, owner, spender);
    }
  }

  function _requireMinERC1155Balance(address token, address owner, uint256 tokenId, uint256 minBalance) private view {
    uint256 balance = IERC1155(token).balanceOf(owner, tokenId);
    if (balance < minBalance) {
      revert ERC1155BalanceTooLow(token, owner, tokenId, balance, minBalance);
    }
  }

  function _requireMinERC1155BalanceBatch(
    address token,
    address owner,
    uint256[] calldata tokenIds,
    uint256[] calldata minBalances
  ) private view {
    if (tokenIds.length != minBalances.length) {
      revert LengthMismatch(tokenIds.length, minBalances.length);
    }

    uint256 length = tokenIds.length;
    address[] memory accounts = new address[](length);
    for (uint256 i = 0; i < length; i++) {
      accounts[i] = owner;
    }

    uint256[] memory balances = IERC1155(token).balanceOfBatch(accounts, tokenIds);
    for (uint256 i = 0; i < length; i++) {
      if (balances[i] < minBalances[i]) {
        revert ERC1155BatchBalanceTooLow(i, balances[i], minBalances[i]);
      }
    }
  }

  function _requireERC1155Approval(address token, address owner, address operator) private view {
    bool isApproved = IERC1155(token).isApprovedForAll(owner, operator);
    if (!isApproved) {
      revert ERC1155NotApproved(token, owner, operator);
    }
  }

  /// @notice Reverts if `block.timestamp` is greater than or equal to `expiration`.
  function requireNonExpired(uint256 expiration) external view {
    if (block.timestamp >= expiration) {
      revert Expired(expiration, block.timestamp);
    }
  }

  /// @notice Reverts if `owner` has less than `minBalance` native tokens.
  function requireMinBalance(address owner, uint256 minBalance) external view {
    _requireMinBalance(owner, minBalance);
  }

  /// @notice Reverts if `address(this)` has less than `minBalance` native tokens.
  function requireMinBalanceSelf(uint256 minBalance) external view {
    _requireMinBalance(address(this), minBalance);
  }

  /// @notice Reverts if `owner` has less than `minBalance` of `token`.
  function requireMinERC20Balance(address token, address owner, uint256 minBalance) external view {
    _requireMinERC20Balance(token, owner, minBalance);
  }

  /// @notice Reverts if `address(this)` has less than `minBalance` of `token`.
  function requireMinERC20BalanceSelf(address token, uint256 minBalance) external view {
    _requireMinERC20Balance(token, address(this), minBalance);
  }

  /// @notice Reverts if `owner` has granted `spender` less than `minAllowance` for `token`.
  function requireMinERC20Allowance(address token, address owner, address spender, uint256 minAllowance) external view {
    _requireMinERC20Allowance(token, owner, spender, minAllowance);
  }

  /// @notice Reverts if `address(this)` has granted `spender` less than `minAllowance` for `token`.
  function requireMinERC20AllowanceSelf(address token, address spender, uint256 minAllowance) external view {
    _requireMinERC20Allowance(token, address(this), spender, minAllowance);
  }

  /// @notice Reverts if `owner` has less than `minAmount` of `token` and granted `spender` less than `minAmount` for `token`.
  function requireMinERC20BalanceAllowance(address token, address owner, address spender, uint256 minAmount)
    external
    view
  {
    _requireMinERC20Balance(token, owner, minAmount);
    _requireMinERC20Allowance(token, owner, spender, minAmount);
  }

  /// @notice Reverts if `address(this)` has less than `minAmount` of `token` and granted `spender` less than `minAmount` for `token`.
  function requireMinERC20BalanceAllowanceSelf(address token, address spender, uint256 minAmount) external view {
    _requireMinERC20Balance(token, address(this), minAmount);
    _requireMinERC20Allowance(token, address(this), spender, minAmount);
  }

  /// @notice Reverts if `owner` is not the owner of `tokenId` on `token` (ERC721).
  function requireERC721Owner(address token, address owner, uint256 tokenId) external view {
    _requireERC721Owner(token, owner, tokenId);
  }

  /// @notice Reverts if `address(this)` is not the owner of `tokenId` on `token` (ERC721).
  function requireERC721OwnerSelf(address token, uint256 tokenId) external view {
    _requireERC721Owner(token, address(this), tokenId);
  }

  /// @notice Reverts if `spender` is not approved to transfer `tokenId` from `owner` on `token` (ERC721).
  function requireERC721Approval(address token, address owner, address spender, uint256 tokenId) external view {
    _requireERC721Approval(token, owner, spender, tokenId);
  }

  /// @notice Reverts if `spender` is not approved to transfer `tokenId` from `address(this)` on `token` (ERC721).
  function requireERC721ApprovalSelf(address token, address spender, uint256 tokenId) external view {
    _requireERC721Approval(token, address(this), spender, tokenId);
  }

  /// @notice Reverts if `owner` is not the owner of `tokenId` on `token` (ERC721) and `spender` is not approved to transfer `tokenId` from `owner` on `token`.
  function requireERC721OwnerApproval(address token, address owner, address spender, uint256 tokenId) external view {
    _requireERC721Owner(token, owner, tokenId);
    _requireERC721Approval(token, owner, spender, tokenId);
  }

  /// @notice Reverts if `address(this)` is not the owner of `tokenId` on `token` (ERC721) and `spender` is not approved to transfer `tokenId` from `address(this)` on `token`.
  function requireERC721OwnerApprovalSelf(address token, address spender, uint256 tokenId) external view {
    _requireERC721Owner(token, address(this), tokenId);
    _requireERC721Approval(token, address(this), spender, tokenId);
  }

  /// @notice Reverts if `owner` has less than `minBalance` of `tokenId` on `token` (ERC1155).
  function requireMinERC1155Balance(address token, address owner, uint256 tokenId, uint256 minBalance) external view {
    _requireMinERC1155Balance(token, owner, tokenId, minBalance);
  }

  /// @notice Reverts if `address(this)` has less than `minBalance` of `tokenId` on `token` (ERC1155).
  function requireMinERC1155BalanceSelf(address token, uint256 tokenId, uint256 minBalance) external view {
    _requireMinERC1155Balance(token, address(this), tokenId, minBalance);
  }

  /// @notice Reverts if any `tokenIds[i]` balance of `owner` is below `minBalances[i]` (ERC1155 batch).
  function requireMinERC1155BalanceBatch(
    address token,
    address owner,
    uint256[] calldata tokenIds,
    uint256[] calldata minBalances
  ) external view {
    _requireMinERC1155BalanceBatch(token, owner, tokenIds, minBalances);
  }

  /// @notice Reverts if any `tokenIds[i]` balance of `address(this)` is below `minBalances[i]` (ERC1155 batch).
  function requireMinERC1155BalanceBatchSelf(address token, uint256[] calldata tokenIds, uint256[] calldata minBalances)
    external
    view
  {
    _requireMinERC1155BalanceBatch(token, address(this), tokenIds, minBalances);
  }

  /// @notice Reverts if `operator` is not approved for all of `owner`'s tokens on `token` (ERC1155).
  function requireERC1155Approval(address token, address owner, address operator) external view {
    _requireERC1155Approval(token, owner, operator);
  }

  /// @notice Reverts if `operator` is not approved for all of `address(this)`'s tokens on `token` (ERC1155).
  function requireERC1155ApprovalSelf(address token, address operator) external view {
    _requireERC1155Approval(token, address(this), operator);
  }

  /// @notice Reverts if `owner` has less than `minBalance` of `tokenId` on `token` (ERC1155) and `operator` is not approved to transfer `tokenId` from `owner` on `token` (ERC1155).
  function requireMinERC1155BalanceApproval(
    address token,
    address owner,
    uint256 tokenId,
    uint256 minBalance,
    address operator
  ) external view {
    _requireMinERC1155Balance(token, owner, tokenId, minBalance);
    _requireERC1155Approval(token, owner, operator);
  }

  /// @notice Reverts if `address(this)` has less than `minBalance` of `tokenId` on `token` (ERC1155) and `operator` is not approved to transfer `tokenId` from `address(this)` on `token` (ERC1155).
  function requireMinERC1155BalanceApprovalSelf(address token, uint256 tokenId, uint256 minBalance, address operator)
    external
    view
  {
    _requireMinERC1155Balance(token, address(this), tokenId, minBalance);
    _requireERC1155Approval(token, address(this), operator);
  }

  /// @notice Reverts if any `tokenIds[i]` balance of `owner` is below `minBalances[i]` (ERC1155 batch) and `operator` is not approved to transfer `tokenIds[i]` from `owner` on `token` (ERC1155).
  function requireMinERC1155BalanceApprovalBatch(
    address token,
    address owner,
    uint256[] calldata tokenIds,
    uint256[] calldata minBalances,
    address operator
  ) external view {
    _requireMinERC1155BalanceBatch(token, owner, tokenIds, minBalances);
    _requireERC1155Approval(token, owner, operator);
  }

  /// @notice Reverts if any `tokenIds[i]` balance of `address(this)` is below `minBalances[i]` (ERC1155 batch) and `operator` is not approved to transfer `tokenIds[i]` from `address(this)` on `token` (ERC1155).
  function requireMinERC1155BalanceApprovalBatchSelf(
    address token,
    uint256[] calldata tokenIds,
    uint256[] calldata minBalances,
    address operator
  ) external view {
    _requireMinERC1155BalanceBatch(token, address(this), tokenIds, minBalances);
    _requireERC1155Approval(token, address(this), operator);
  }
}
