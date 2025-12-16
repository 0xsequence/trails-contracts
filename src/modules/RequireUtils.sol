// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

contract RequireUtils {
  error Expired(uint256 expiration, uint256 timestamp);
  error NonceBelowRequired(uint256 space, uint256 current, uint256 required);
  error ERC20BalanceTooLow(address token, address wallet, uint256 balance, uint256 minBalance);
  error ERC20AllowanceTooLow(address token, address owner, address spender, uint256 allowance, uint256 minAllowance);
  error ERC721NotApproved(address token, uint256 tokenId, address owner, address spender);
  error ERC1155BalanceTooLow(address token, address wallet, uint256 tokenId, uint256 balance, uint256 minBalance);
  error ERC1155ZeroBalance(address token, address wallet, uint256 tokenId);
  error LengthMismatch(uint256 a, uint256 b);
  error ERC1155BatchBalanceTooLow(uint256 index, uint256 balance, uint256 minBalance);
  error ERC1155NotApproved(address token, address owner, address operator);
  error ERC1155IsApproved(address token, address owner, address operator);
  error MsgValueTooLow(uint256 value, uint256 minValue);
  error ZeroMsgValue();
  error NativeBalanceTooLow(address wallet, uint256 balance, uint256 minBalance);

  function _requireMinBalance(address wallet, uint256 minBalance) private view {
    uint256 balance = wallet.balance;
    if (balance < minBalance) {
      revert NativeBalanceTooLow(wallet, balance, minBalance);
    }
  }

  function _requireMinERC20Balance(address token, address wallet, uint256 minBalance) private view {
    uint256 balance = IERC20(token).balanceOf(wallet);
    if (balance < minBalance) {
      revert ERC20BalanceTooLow(token, wallet, balance, minBalance);
    }
  }

  function _requireMinERC20Allowance(address token, address owner, address spender, uint256 minAllowance) private view {
    uint256 allowance = IERC20(token).allowance(owner, spender);
    if (allowance < minAllowance) {
      revert ERC20AllowanceTooLow(token, owner, spender, allowance, minAllowance);
    }
  }

  function _requireERC721Approval(address token, address owner, address spender, uint256 tokenId) private view {
    address approved = IERC721(token).getApproved(tokenId);
    if (approved != spender && !IERC721(token).isApprovedForAll(owner, spender)) {
      revert ERC721NotApproved(token, tokenId, owner, spender);
    }
  }

  function _requireMinERC1155Balance(address token, address wallet, uint256 tokenId, uint256 minBalance) private view {
    uint256 balance = IERC1155(token).balanceOf(wallet, tokenId);
    if (balance < minBalance) {
      revert ERC1155BalanceTooLow(token, wallet, tokenId, balance, minBalance);
    }
  }

  function _requireMinERC1155BalanceBatch(
    address token,
    address wallet,
    uint256[] calldata tokenIds,
    uint256[] calldata minBalances
  ) private view {
    if (tokenIds.length != minBalances.length) {
      revert LengthMismatch(tokenIds.length, minBalances.length);
    }

    uint256 length = tokenIds.length;
    address[] memory accounts = new address[](length);
    for (uint256 i = 0; i < length; i++) {
      accounts[i] = wallet;
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

  function requireNonExpired(uint256 expiration) external view {
    if (block.timestamp >= expiration) {
      revert Expired(expiration, block.timestamp);
    }
  }

  function requireMinBalance(address wallet, uint256 minBalance) external view {
    _requireMinBalance(wallet, minBalance);
  }

  function requireMinBalanceSelf(uint256 minBalance) external view {
    _requireMinBalance(msg.sender, minBalance);
  }

  function requireMinERC20Balance(address token, address wallet, uint256 minBalance) external view {
    _requireMinERC20Balance(token, wallet, minBalance);
  }

  function requireMinERC20BalanceSelf(address token, uint256 minBalance) external view {
    _requireMinERC20Balance(token, msg.sender, minBalance);
  }

  function requireMinERC20Allowance(address token, address owner, address spender, uint256 minAllowance) external view {
    _requireMinERC20Allowance(token, owner, spender, minAllowance);
  }

  function requireMinERC20AllowanceSelf(address token, address spender, uint256 minAllowance) external view {
    _requireMinERC20Allowance(token, msg.sender, spender, minAllowance);
  }

  function requireERC721Approval(address token, address owner, address spender, uint256 tokenId) external view {
    _requireERC721Approval(token, owner, spender, tokenId);
  }

  function requireERC721ApprovalSelf(address token, address spender, uint256 tokenId) external view {
    _requireERC721Approval(token, msg.sender, spender, tokenId);
  }

  function requireMinERC1155Balance(address token, address wallet, uint256 tokenId, uint256 minBalance) external view {
    _requireMinERC1155Balance(token, wallet, tokenId, minBalance);
  }

  function requireMinERC1155BalanceSelf(address token, uint256 tokenId, uint256 minBalance) external view {
    _requireMinERC1155Balance(token, msg.sender, tokenId, minBalance);
  }

  function requireMinERC1155BalanceBatch(
    address token,
    address wallet,
    uint256[] calldata tokenIds,
    uint256[] calldata minBalances
  ) external view {
    _requireMinERC1155BalanceBatch(token, wallet, tokenIds, minBalances);
  }

  function requireMinERC1155BalanceBatchSelf(address token, uint256[] calldata tokenIds, uint256[] calldata minBalances)
    external
    view
  {
    _requireMinERC1155BalanceBatch(token, msg.sender, tokenIds, minBalances);
  }

  function requireERC1155Approval(address token, address owner, address operator) external view {
    _requireERC1155Approval(token, owner, operator);
  }

  function requireERC1155ApprovalSelf(address token, address operator) external view {
    _requireERC1155Approval(token, msg.sender, operator);
  }
}
