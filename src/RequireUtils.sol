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

  function requireNonExpired(uint256 expiration) external view {
    if (block.timestamp >= expiration) {
      revert Expired(expiration, block.timestamp);
    }
  }

  function requireMinBalance(address wallet, uint256 minBalance) external view {
    uint256 balance = wallet.balance;
    if (balance < minBalance) {
      revert NativeBalanceTooLow(wallet, balance, minBalance);
    }
  }

  function requireMinERC20Balance(address token, address wallet, uint256 minBalance) external view {
    uint256 balance = IERC20(token).balanceOf(wallet);
    if (balance < minBalance) {
      revert ERC20BalanceTooLow(token, wallet, balance, minBalance);
    }
  }

  function requireMinERC20Allowance(address token, address owner, address spender, uint256 minAllowance) external view {
    uint256 allowance = IERC20(token).allowance(owner, spender);
    if (allowance < minAllowance) {
      revert ERC20AllowanceTooLow(token, owner, spender, allowance, minAllowance);
    }
  }

  function requireERC721Approval(address token, address owner, address spender, uint256 tokenId) external view {
    address approved = IERC721(token).getApproved(tokenId);
    if (approved != spender && !IERC721(token).isApprovedForAll(owner, spender)) {
      revert ERC721NotApproved(token, tokenId, owner, spender);
    }
  }

  function requireMinERC1155Balance(address token, address wallet, uint256 tokenId, uint256 minBalance) external view {
    uint256 balance = IERC1155(token).balanceOf(wallet, tokenId);
    if (balance < minBalance) {
      revert ERC1155BalanceTooLow(token, wallet, tokenId, balance, minBalance);
    }
  }

  function requireMinERC1155BalanceBatch(
    address token,
    address wallet,
    uint256[] calldata tokenIds,
    uint256[] calldata minBalances
  ) external view {
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

  function requireERC1155Approval(address token, address owner, address operator) external view {
    bool isApproved = IERC1155(token).isApprovedForAll(owner, operator);
    if (!isApproved) {
      revert ERC1155NotApproved(token, owner, operator);
    }
  }
}
