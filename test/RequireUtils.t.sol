// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import "forge-std/Test.sol";

import {RequireUtils} from "src/modules/RequireUtils.sol";
import {MockERC1155, MockERC20, MockERC721} from "test/helpers/Mocks.sol";

contract RequireUtilsTest is Test {
  function testFuzz_requireNonExpired(uint48 nowTs, uint48 expiration) external {
    RequireUtils utils = new RequireUtils();

    vm.warp(uint256(nowTs));
    if (uint256(nowTs) >= uint256(expiration)) {
      vm.expectRevert(abi.encodeWithSelector(RequireUtils.Expired.selector, uint256(expiration), uint256(nowTs)));
      utils.requireNonExpired(uint256(expiration));
      return;
    }

    utils.requireNonExpired(uint256(expiration));
  }

  function testFuzz_requireMinBalance(address wallet, uint96 balance, uint96 minBalance) external {
    RequireUtils utils = new RequireUtils();
    vm.deal(wallet, balance);

    if (balance < minBalance) {
      vm.expectRevert(
        abi.encodeWithSelector(RequireUtils.NativeBalanceTooLow.selector, wallet, uint256(balance), uint256(minBalance))
      );
      utils.requireMinBalance(wallet, minBalance);
      return;
    }

    utils.requireMinBalance(wallet, minBalance);
  }

  function testFuzz_requireMinBalanceSelf(address sender, uint96 balance, uint96 minBalance) external {
    RequireUtils utils = new RequireUtils();
    vm.deal(sender, balance);

    vm.prank(sender);
    if (balance < minBalance) {
      vm.expectRevert(
        abi.encodeWithSelector(RequireUtils.NativeBalanceTooLow.selector, sender, uint256(balance), uint256(minBalance))
      );
      utils.requireMinBalanceSelf(minBalance);
      return;
    }

    utils.requireMinBalanceSelf(minBalance);
  }

  function testFuzz_requireMinERC20Balance(address wallet, uint128 bal, uint128 minBal) external {
    RequireUtils utils = new RequireUtils();
    MockERC20 token = new MockERC20();

    token.mint(wallet, bal);

    if (bal < minBal) {
      vm.expectRevert(
        abi.encodeWithSelector(
          RequireUtils.ERC20BalanceTooLow.selector, address(token), wallet, uint256(bal), uint256(minBal)
        )
      );
      utils.requireMinERC20Balance(address(token), wallet, minBal);
      return;
    }

    utils.requireMinERC20Balance(address(token), wallet, minBal);
  }

  function testFuzz_requireMinERC20BalanceSelf(address sender, uint128 bal, uint128 minBal) external {
    RequireUtils utils = new RequireUtils();
    MockERC20 token = new MockERC20();

    token.mint(sender, bal);

    vm.prank(sender);
    if (bal < minBal) {
      vm.expectRevert(
        abi.encodeWithSelector(
          RequireUtils.ERC20BalanceTooLow.selector, address(token), sender, uint256(bal), uint256(minBal)
        )
      );
      utils.requireMinERC20BalanceSelf(address(token), minBal);
      return;
    }

    utils.requireMinERC20BalanceSelf(address(token), minBal);
  }

  function testFuzz_requireMinERC20Allowance(address owner, address spender, uint128 allowance_, uint128 minAllowance)
    external
  {
    RequireUtils utils = new RequireUtils();
    MockERC20 token = new MockERC20();

    vm.prank(owner);
    token.approve(spender, allowance_);

    if (allowance_ < minAllowance) {
      vm.expectRevert(
        abi.encodeWithSelector(
          RequireUtils.ERC20AllowanceTooLow.selector,
          address(token),
          owner,
          spender,
          uint256(allowance_),
          uint256(minAllowance)
        )
      );
      utils.requireMinERC20Allowance(address(token), owner, spender, minAllowance);
      return;
    }

    utils.requireMinERC20Allowance(address(token), owner, spender, minAllowance);
  }

  function testFuzz_requireMinERC20AllowanceSelf(
    address owner,
    address spender,
    uint128 allowance_,
    uint128 minAllowance
  ) external {
    RequireUtils utils = new RequireUtils();
    MockERC20 token = new MockERC20();

    vm.prank(owner);
    token.approve(spender, allowance_);

    vm.prank(owner);
    if (allowance_ < minAllowance) {
      vm.expectRevert(
        abi.encodeWithSelector(
          RequireUtils.ERC20AllowanceTooLow.selector,
          address(token),
          owner,
          spender,
          uint256(allowance_),
          uint256(minAllowance)
        )
      );
      utils.requireMinERC20AllowanceSelf(address(token), spender, minAllowance);
      return;
    }

    utils.requireMinERC20AllowanceSelf(address(token), spender, minAllowance);
  }

  function testFuzz_requireERC721Approval(
    address owner,
    address spender,
    uint256 tokenId,
    address approved,
    bool approvedForAll
  ) external {
    RequireUtils utils = new RequireUtils();
    MockERC721 token = new MockERC721();

    token.setApproved(tokenId, approved);
    token.setApprovedForAll(owner, spender, approvedForAll);

    if (approved != spender && !approvedForAll) {
      vm.expectRevert(
        abi.encodeWithSelector(RequireUtils.ERC721NotApproved.selector, address(token), tokenId, owner, spender)
      );
      utils.requireERC721Approval(address(token), owner, spender, tokenId);
      return;
    }

    utils.requireERC721Approval(address(token), owner, spender, tokenId);
  }

  function testFuzz_requireERC721ApprovalSelf(address owner, address spender, uint256 tokenId, address approved, bool approvedForAll)
    external
  {
    RequireUtils utils = new RequireUtils();
    MockERC721 token = new MockERC721();

    token.setApproved(tokenId, approved);
    token.setApprovedForAll(owner, spender, approvedForAll);

    vm.prank(owner);
    if (approved != spender && !approvedForAll) {
      vm.expectRevert(
        abi.encodeWithSelector(RequireUtils.ERC721NotApproved.selector, address(token), tokenId, owner, spender)
      );
      utils.requireERC721ApprovalSelf(address(token), spender, tokenId);
      return;
    }

    utils.requireERC721ApprovalSelf(address(token), spender, tokenId);
  }

  function testFuzz_requireMinERC1155Balance(address wallet, uint256 tokenId, uint128 bal, uint128 minBal) external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    token.mint(wallet, tokenId, bal);

    if (bal < minBal) {
      vm.expectRevert(
        abi.encodeWithSelector(
          RequireUtils.ERC1155BalanceTooLow.selector, address(token), wallet, tokenId, uint256(bal), uint256(minBal)
        )
      );
      utils.requireMinERC1155Balance(address(token), wallet, tokenId, minBal);
      return;
    }

    utils.requireMinERC1155Balance(address(token), wallet, tokenId, minBal);
  }

  function testFuzz_requireMinERC1155BalanceSelf(address owner, uint256 tokenId, uint128 bal, uint128 minBal) external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    token.mint(owner, tokenId, bal);

    vm.prank(owner);
    if (bal < minBal) {
      vm.expectRevert(
        abi.encodeWithSelector(
          RequireUtils.ERC1155BalanceTooLow.selector, address(token), owner, tokenId, uint256(bal), uint256(minBal)
        )
      );
      utils.requireMinERC1155BalanceSelf(address(token), tokenId, minBal);
      return;
    }

    utils.requireMinERC1155BalanceSelf(address(token), tokenId, minBal);
  }

  function test_requireMinERC1155BalanceBatch_reverts_lengthMismatch() external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    uint256[] memory tokenIds = new uint256[](2);
    uint256[] memory minBalances = new uint256[](1);

    vm.expectRevert(abi.encodeWithSelector(RequireUtils.LengthMismatch.selector, uint256(2), uint256(1)));
    utils.requireMinERC1155BalanceBatch(address(token), address(this), tokenIds, minBalances);
  }

  function testFuzz_requireMinERC1155BalanceBatch_passes(address wallet, uint256[] calldata tokenIds, bytes32 seed) external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    vm.assume(tokenIds.length > 0);
    vm.assume(tokenIds.length <= 5);

    uint256[] memory minBalances = new uint256[](tokenIds.length);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 bal = uint256(keccak256(abi.encodePacked(seed, i))) % 1_000_000;
      token.mint(wallet, tokenIds[i], bal);
      minBalances[i] = token.balanceOf(wallet, tokenIds[i]);
    }

    utils.requireMinERC1155BalanceBatch(address(token), wallet, tokenIds, minBalances);
  }

  function testFuzz_requireMinERC1155BalanceBatch_reverts_firstIndex(address wallet, uint256[] calldata tokenIds, bytes32 seed)
    external
  {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    vm.assume(tokenIds.length > 0);
    vm.assume(tokenIds.length <= 5);

    uint256[] memory minBalances = new uint256[](tokenIds.length);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 bal = uint256(keccak256(abi.encodePacked(seed, i))) % 1_000_000;
      token.mint(wallet, tokenIds[i], bal);
      minBalances[i] = 0;
    }

    uint256 bal0 = token.balanceOf(wallet, tokenIds[0]);
    minBalances[0] = bal0 + 1;

    vm.expectRevert(abi.encodeWithSelector(RequireUtils.ERC1155BatchBalanceTooLow.selector, uint256(0), bal0, bal0 + 1));
    utils.requireMinERC1155BalanceBatch(address(token), wallet, tokenIds, minBalances);
  }

  function testFuzz_requireMinERC1155BalanceBatchSelf_passes(address owner, uint256[] calldata tokenIds, bytes32 seed)
    external
  {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    vm.assume(tokenIds.length > 0);
    vm.assume(tokenIds.length <= 5);

    uint256[] memory minBalances = new uint256[](tokenIds.length);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 bal = uint256(keccak256(abi.encodePacked(seed, i))) % 1_000_000;
      token.mint(owner, tokenIds[i], bal);
      minBalances[i] = token.balanceOf(owner, tokenIds[i]);
    }

    vm.prank(owner);
    utils.requireMinERC1155BalanceBatchSelf(address(token), tokenIds, minBalances);
  }

  function testFuzz_requireMinERC1155BalanceBatchSelf_reverts_firstIndex(
    address owner,
    uint256[] calldata tokenIds,
    bytes32 seed
  ) external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    vm.assume(tokenIds.length > 0);
    vm.assume(tokenIds.length <= 5);

    uint256[] memory minBalances = new uint256[](tokenIds.length);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 bal = uint256(keccak256(abi.encodePacked(seed, i))) % 1_000_000;
      token.mint(owner, tokenIds[i], bal);
      minBalances[i] = 0;
    }

    uint256 bal0 = token.balanceOf(owner, tokenIds[0]);
    minBalances[0] = bal0 + 1;

    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(RequireUtils.ERC1155BatchBalanceTooLow.selector, uint256(0), bal0, bal0 + 1));
    utils.requireMinERC1155BalanceBatchSelf(address(token), tokenIds, minBalances);
  }

  function testFuzz_requireERC1155Approval(address owner, address operator, bool approved) external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    token.setApprovedForAll(owner, operator, approved);

    if (!approved) {
      vm.expectRevert(abi.encodeWithSelector(RequireUtils.ERC1155NotApproved.selector, address(token), owner, operator));
      utils.requireERC1155Approval(address(token), owner, operator);
      return;
    }

    utils.requireERC1155Approval(address(token), owner, operator);
  }

  function testFuzz_requireERC1155ApprovalSelf(address owner, address operator, bool approved) external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    token.setApprovedForAll(owner, operator, approved);

    vm.prank(owner);
    if (!approved) {
      vm.expectRevert(abi.encodeWithSelector(RequireUtils.ERC1155NotApproved.selector, address(token), owner, operator));
      utils.requireERC1155ApprovalSelf(address(token), operator);
      return;
    }

    utils.requireERC1155ApprovalSelf(address(token), operator);
  }
}

