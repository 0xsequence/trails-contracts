// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {RequireUtils} from "src/modules/RequireUtils.sol";
import {MockERC1155, MockERC20, MockERC721} from "test/helpers/Mocks.sol";

contract Wallet {
  function delegateCall(address target, bytes memory data) public returns (bool success, bytes memory result) {
    (success, result) = target.delegatecall(data);
    return (success, result);
  }
}

contract RequireUtilsTest is Test {
  Wallet public wallet;

  function setUp() public {
    wallet = new Wallet();
  }

  function testFuzz_requireNonExpired(uint48 nowTs, uint48 expiration) external {
    RequireUtils utils = new RequireUtils();

    vm.warp(uint256(nowTs));
    if (uint256(nowTs) >= uint256(expiration)) {
      vm.expectRevert(abi.encodeWithSelector(RequireUtils.Expired.selector, uint256(expiration), uint256(nowTs)));
    }

    utils.requireNonExpired(uint256(expiration));
  }

  function testFuzz_requireMinBalance(address owner, uint96 balance, uint96 minBalance) external {
    RequireUtils utils = new RequireUtils();
    vm.deal(owner, balance);

    if (balance < minBalance) {
      vm.expectRevert(
        abi.encodeWithSelector(RequireUtils.NativeBalanceTooLow.selector, owner, uint256(balance), uint256(minBalance))
      );
    }

    utils.requireMinBalance(owner, minBalance);
  }

  function testFuzz_requireMinBalanceSelf(uint96 balance, uint96 minBalance) external {
    RequireUtils utils = new RequireUtils();
    vm.deal(address(wallet), balance);

    bool expectedSuccess = true;
    bytes memory expectedData;

    if (balance < minBalance) {
      expectedSuccess = false;
      expectedData = abi.encodeWithSelector(
        RequireUtils.NativeBalanceTooLow.selector, address(wallet), uint256(balance), uint256(minBalance)
      );
    }

    (bool success, bytes memory result) = wallet.delegateCall(
      address(utils), abi.encodeWithSelector(RequireUtils.requireMinBalanceSelf.selector, minBalance)
    );
    assertEq(success, expectedSuccess);
    assertEq(result, expectedData);
  }

  function testFuzz_requireMinERC20Balance(address owner, uint128 bal, uint128 minBal) external {
    RequireUtils utils = new RequireUtils();
    MockERC20 token = new MockERC20();

    token.mint(owner, bal);

    if (bal < minBal) {
      vm.expectRevert(
        abi.encodeWithSelector(
          RequireUtils.ERC20BalanceTooLow.selector, address(token), owner, uint256(bal), uint256(minBal)
        )
      );
    }

    utils.requireMinERC20Balance(address(token), owner, minBal);
  }

  function testFuzz_requireMinERC20BalanceSelf(uint128 bal, uint128 minBal) external {
    RequireUtils utils = new RequireUtils();
    MockERC20 token = new MockERC20();

    token.mint(address(wallet), bal);

    bool expectedSuccess = true;
    bytes memory expectedData;

    if (bal < minBal) {
      expectedSuccess = false;
      expectedData = abi.encodeWithSelector(
        RequireUtils.ERC20BalanceTooLow.selector, address(token), address(wallet), uint256(bal), uint256(minBal)
      );
    }

    (bool success, bytes memory result) = wallet.delegateCall(
      address(utils), abi.encodeWithSelector(RequireUtils.requireMinERC20BalanceSelf.selector, address(token), minBal)
    );
    assertEq(success, expectedSuccess);
    assertEq(result, expectedData);
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
    }

    utils.requireMinERC20Allowance(address(token), owner, spender, minAllowance);
  }

  function testFuzz_requireMinERC20AllowanceSelf(address spender, uint128 allowance_, uint128 minAllowance) external {
    RequireUtils utils = new RequireUtils();
    MockERC20 token = new MockERC20();

    vm.prank(address(wallet));
    token.approve(spender, allowance_);

    bool expectedSuccess = true;
    bytes memory expectedData;

    if (allowance_ < minAllowance) {
      expectedSuccess = false;
      expectedData = abi.encodeWithSelector(
        RequireUtils.ERC20AllowanceTooLow.selector,
        address(token),
        address(wallet),
        spender,
        uint256(allowance_),
        uint256(minAllowance)
      );
    }

    (bool success, bytes memory result) = wallet.delegateCall(
      address(utils),
      abi.encodeWithSelector(RequireUtils.requireMinERC20AllowanceSelf.selector, address(token), spender, minAllowance)
    );
    assertEq(success, expectedSuccess);
    assertEq(result, expectedData);
  }

  function testFuzz_requireMinERC20BalanceAllowance(
    address owner,
    address spender,
    uint128 bal,
    uint128 allowance,
    uint128 minAmount
  ) external {
    RequireUtils utils = new RequireUtils();
    MockERC20 token = new MockERC20();

    token.mint(owner, bal);
    vm.prank(owner);
    token.approve(spender, allowance);

    if (bal < minAmount) {
      vm.expectRevert(
        abi.encodeWithSelector(
          RequireUtils.ERC20BalanceTooLow.selector, address(token), owner, uint256(bal), uint256(minAmount)
        )
      );
    } else if (allowance < minAmount) {
      vm.expectRevert(
        abi.encodeWithSelector(
          RequireUtils.ERC20AllowanceTooLow.selector,
          address(token),
          owner,
          spender,
          uint256(allowance),
          uint256(minAmount)
        )
      );
    }

    utils.requireMinERC20BalanceAllowance(address(token), owner, spender, minAmount);
  }

  function testFuzz_requireMinERC20BalanceAllowanceSelf(
    address spender,
    uint128 bal,
    uint128 allowance,
    uint128 minAmount
  ) external {
    RequireUtils utils = new RequireUtils();
    MockERC20 token = new MockERC20();

    token.mint(address(wallet), bal);
    vm.prank(address(wallet));
    token.approve(spender, allowance);

    bool expectedSuccess = true;
    bytes memory expectedData;

    if (bal < minAmount) {
      expectedSuccess = false;
      expectedData = abi.encodeWithSelector(
        RequireUtils.ERC20BalanceTooLow.selector, address(token), address(wallet), uint256(bal), uint256(minAmount)
      );
    } else if (allowance < minAmount) {
      expectedSuccess = false;
      expectedData = abi.encodeWithSelector(
        RequireUtils.ERC20AllowanceTooLow.selector,
        address(token),
        address(wallet),
        spender,
        uint256(allowance),
        uint256(minAmount)
      );
    }

    (bool success, bytes memory result) = wallet.delegateCall(
      address(utils),
      abi.encodeWithSelector(
        RequireUtils.requireMinERC20BalanceAllowanceSelf.selector, address(token), spender, minAmount
      )
    );
    assertEq(success, expectedSuccess);
    assertEq(result, expectedData);
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
    }

    utils.requireERC721Approval(address(token), owner, spender, tokenId);
  }

  function testFuzz_requireERC721ApprovalSelf(address spender, uint256 tokenId, address approved, bool approvedForAll)
    external
  {
    RequireUtils utils = new RequireUtils();
    MockERC721 token = new MockERC721();

    token.setOwner(tokenId, address(wallet));
    token.setApproved(tokenId, approved);
    token.setApprovedForAll(address(wallet), spender, approvedForAll);

    bool expectedSuccess = true;
    bytes memory expectedData;

    if (approved != spender && !approvedForAll) {
      expectedSuccess = false;
      expectedData = abi.encodeWithSelector(
        RequireUtils.ERC721NotApproved.selector, address(token), tokenId, address(wallet), spender
      );
    }

    (bool success, bytes memory result) = wallet.delegateCall(
      address(utils),
      abi.encodeWithSelector(RequireUtils.requireERC721ApprovalSelf.selector, address(token), spender, tokenId)
    );
    assertEq(success, expectedSuccess);
    assertEq(result, expectedData);
  }

  function testFuzz_requireERC721Owner(address actualOwner, uint256 tokenId, address requiredOwner) external {
    RequireUtils utils = new RequireUtils();
    MockERC721 token = new MockERC721();

    token.setOwner(tokenId, actualOwner);

    if (actualOwner != requiredOwner) {
      vm.expectRevert(
        abi.encodeWithSelector(
          RequireUtils.ERC721NotOwner.selector, address(token), tokenId, actualOwner, requiredOwner
        )
      );
    }

    utils.requireERC721Owner(address(token), requiredOwner, tokenId);
  }

  function testFuzz_requireERC721OwnerSelf(uint256 tokenId) external {
    RequireUtils utils = new RequireUtils();
    MockERC721 token = new MockERC721();

    token.setOwner(tokenId, address(wallet));

    bool expectedSuccess = true;
    bytes memory expectedData;

    (bool success, bytes memory result) = wallet.delegateCall(
      address(utils), abi.encodeWithSelector(RequireUtils.requireERC721OwnerSelf.selector, address(token), tokenId)
    );
    assertEq(success, expectedSuccess);
    assertEq(result, expectedData);
  }

  function testFuzz_requireERC721Approval(
    address requiredOwner,
    address spender,
    uint256 tokenId,
    address actualOwner,
    address approved,
    bool approvedForAll
  ) external {
    RequireUtils utils = new RequireUtils();
    MockERC721 token = new MockERC721();

    token.setOwner(tokenId, actualOwner);
    token.setApproved(tokenId, approved);
    token.setApprovedForAll(requiredOwner, spender, approvedForAll);

    if (actualOwner != requiredOwner) {
      vm.expectRevert(
        abi.encodeWithSelector(
          RequireUtils.ERC721NotOwner.selector, address(token), tokenId, actualOwner, requiredOwner
        )
      );
    } else if (approved != spender && !approvedForAll) {
      vm.expectRevert(
        abi.encodeWithSelector(RequireUtils.ERC721NotApproved.selector, address(token), tokenId, requiredOwner, spender)
      );
    }

    utils.requireERC721OwnerApproval(address(token), requiredOwner, spender, tokenId);
  }

  function testFuzz_requireERC721OwnerApprovalSelf(
    address spender,
    uint256 tokenId,
    address approved,
    bool approvedForAll
  ) external {
    RequireUtils utils = new RequireUtils();
    MockERC721 token = new MockERC721();

    token.setOwner(tokenId, address(wallet));
    token.setApproved(tokenId, approved);
    token.setApprovedForAll(address(wallet), spender, approvedForAll);

    bool expectedSuccess = true;
    bytes memory expectedData;

    if (approved != spender && !approvedForAll) {
      expectedSuccess = false;
      expectedData = abi.encodeWithSelector(
        RequireUtils.ERC721NotApproved.selector, address(token), tokenId, address(wallet), spender
      );
    }

    (bool success, bytes memory result) = wallet.delegateCall(
      address(utils),
      abi.encodeWithSelector(RequireUtils.requireERC721OwnerApprovalSelf.selector, address(token), spender, tokenId)
    );
    assertEq(success, expectedSuccess);
    assertEq(result, expectedData);
  }

  function testFuzz_requireMinERC1155Balance(address owner, uint256 tokenId, uint128 bal, uint128 minBal) external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    token.mint(owner, tokenId, bal);

    if (bal < minBal) {
      vm.expectRevert(
        abi.encodeWithSelector(
          RequireUtils.ERC1155BalanceTooLow.selector, address(token), owner, tokenId, uint256(bal), uint256(minBal)
        )
      );
    }

    utils.requireMinERC1155Balance(address(token), owner, tokenId, minBal);
  }

  function testFuzz_requireMinERC1155BalanceSelf(uint256 tokenId, uint128 bal, uint128 minBal) external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    token.mint(address(wallet), tokenId, bal);

    bool expectedSuccess = true;
    bytes memory expectedData;

    if (bal < minBal) {
      expectedSuccess = false;
      expectedData = abi.encodeWithSelector(
        RequireUtils.ERC1155BalanceTooLow.selector,
        address(token),
        address(wallet),
        tokenId,
        uint256(bal),
        uint256(minBal)
      );
    }

    (bool success, bytes memory result) = wallet.delegateCall(
      address(utils),
      abi.encodeWithSelector(RequireUtils.requireMinERC1155BalanceSelf.selector, address(token), tokenId, minBal)
    );
    assertEq(success, expectedSuccess);
    assertEq(result, expectedData);
  }

  function test_requireMinERC1155BalanceBatch_reverts_lengthMismatch() external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    uint256[] memory tokenIds = new uint256[](2);
    uint256[] memory minBalances = new uint256[](1);

    vm.expectRevert(abi.encodeWithSelector(RequireUtils.LengthMismatch.selector, uint256(2), uint256(1)));
    utils.requireMinERC1155BalanceBatch(address(token), address(this), tokenIds, minBalances);
  }

  function testFuzz_requireMinERC1155BalanceBatch_passes(address owner, uint256[] calldata tokenIds, bytes32 seed)
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

    utils.requireMinERC1155BalanceBatch(address(token), owner, tokenIds, minBalances);
  }

  function testFuzz_requireMinERC1155BalanceBatch_reverts_firstIndex(
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

    vm.expectRevert(abi.encodeWithSelector(RequireUtils.ERC1155BatchBalanceTooLow.selector, uint256(0), bal0, bal0 + 1));
    utils.requireMinERC1155BalanceBatch(address(token), owner, tokenIds, minBalances);
  }

  function testFuzz_requireMinERC1155BalanceBatchSelf_passes(uint256[] calldata tokenIds, bytes32 seed) external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    vm.assume(tokenIds.length > 0);
    vm.assume(tokenIds.length <= 5);

    uint256[] memory minBalances = new uint256[](tokenIds.length);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 bal = uint256(keccak256(abi.encodePacked(seed, i))) % 1_000_000;
      token.mint(address(wallet), tokenIds[i], bal);
      minBalances[i] = token.balanceOf(address(wallet), tokenIds[i]);
    }

    bool expectedSuccess = true;
    bytes memory expectedData;

    (bool success, bytes memory result) = wallet.delegateCall(
      address(utils),
      abi.encodeWithSelector(
        RequireUtils.requireMinERC1155BalanceBatchSelf.selector, address(token), tokenIds, minBalances
      )
    );
    assertEq(success, expectedSuccess);
    assertEq(result, expectedData);
  }

  function testFuzz_requireMinERC1155BalanceBatchSelf_reverts_firstIndex(uint256[] calldata tokenIds, bytes32 seed)
    external
  {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    vm.assume(tokenIds.length > 0);
    vm.assume(tokenIds.length <= 5);

    uint256[] memory minBalances = new uint256[](tokenIds.length);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 bal = uint256(keccak256(abi.encodePacked(seed, i))) % 1_000_000;
      token.mint(address(wallet), tokenIds[i], bal);
      minBalances[i] = 0;
    }

    uint256 bal0 = token.balanceOf(address(wallet), tokenIds[0]);
    minBalances[0] = bal0 + 1;

    bool expectedSuccess = false;
    bytes memory expectedData =
      abi.encodeWithSelector(RequireUtils.ERC1155BatchBalanceTooLow.selector, uint256(0), bal0, bal0 + 1);

    (bool success, bytes memory result) = wallet.delegateCall(
      address(utils),
      abi.encodeWithSelector(
        RequireUtils.requireMinERC1155BalanceBatchSelf.selector, address(token), tokenIds, minBalances
      )
    );
    assertEq(success, expectedSuccess);
    assertEq(result, expectedData);
  }

  function testFuzz_requireERC1155Approval(address owner, address operator, bool approved) external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    token.setApprovedForAll(owner, operator, approved);

    if (!approved) {
      vm.expectRevert(abi.encodeWithSelector(RequireUtils.ERC1155NotApproved.selector, address(token), owner, operator));
    }

    utils.requireERC1155Approval(address(token), owner, operator);
  }

  function testFuzz_requireERC1155ApprovalSelf(address operator, bool approved) external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    token.setApprovedForAll(address(wallet), operator, approved);

    bool expectedSuccess = true;
    bytes memory expectedData;

    if (!approved) {
      expectedSuccess = false;
      expectedData =
        abi.encodeWithSelector(RequireUtils.ERC1155NotApproved.selector, address(token), address(wallet), operator);
    }

    (bool success, bytes memory result) = wallet.delegateCall(
      address(utils), abi.encodeWithSelector(RequireUtils.requireERC1155ApprovalSelf.selector, address(token), operator)
    );
    assertEq(success, expectedSuccess);
    assertEq(result, expectedData);
  }

  function testFuzz_requireMinERC1155BalanceApproval(
    address owner,
    uint256 tokenId,
    uint128 bal,
    uint128 minBal,
    address operator,
    bool approved
  ) external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    token.mint(owner, tokenId, bal);
    token.setApprovedForAll(owner, operator, approved);

    if (bal < minBal) {
      vm.expectRevert(
        abi.encodeWithSelector(
          RequireUtils.ERC1155BalanceTooLow.selector, address(token), owner, tokenId, uint256(bal), uint256(minBal)
        )
      );
    } else if (!approved) {
      vm.expectRevert(abi.encodeWithSelector(RequireUtils.ERC1155NotApproved.selector, address(token), owner, operator));
    }

    utils.requireMinERC1155BalanceApproval(address(token), owner, tokenId, minBal, operator);
  }

  function testFuzz_requireMinERC1155BalanceApprovalSelf(
    uint256 tokenId,
    uint128 bal,
    uint128 minBal,
    address operator,
    bool approved
  ) external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    token.mint(address(wallet), tokenId, bal);
    token.setApprovedForAll(address(wallet), operator, approved);

    bool expectedSuccess = true;
    bytes memory expectedData;

    if (bal < minBal) {
      expectedSuccess = false;
      expectedData = abi.encodeWithSelector(
        RequireUtils.ERC1155BalanceTooLow.selector,
        address(token),
        address(wallet),
        tokenId,
        uint256(bal),
        uint256(minBal)
      );
    } else if (!approved) {
      expectedSuccess = false;
      expectedData =
        abi.encodeWithSelector(RequireUtils.ERC1155NotApproved.selector, address(token), address(wallet), operator);
    }

    (bool success, bytes memory result) = wallet.delegateCall(
      address(utils),
      abi.encodeWithSelector(
        RequireUtils.requireMinERC1155BalanceApprovalSelf.selector, address(token), tokenId, minBal, operator
      )
    );
    assertEq(success, expectedSuccess);
    assertEq(result, expectedData);
  }

  function testFuzz_requireMinERC1155BalanceApprovalBatch(
    address owner,
    uint256[] calldata tokenIds,
    address operator,
    bool approved,
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
      minBalances[i] = token.balanceOf(owner, tokenIds[i]);
    }

    token.setApprovedForAll(owner, operator, approved);

    if (!approved) {
      vm.expectRevert(abi.encodeWithSelector(RequireUtils.ERC1155NotApproved.selector, address(token), owner, operator));
    }

    utils.requireMinERC1155BalanceApprovalBatch(address(token), owner, tokenIds, minBalances, operator);
  }

  function testFuzz_requireMinERC1155BalanceApprovalBatchSelf(
    uint256[] calldata tokenIds,
    address operator,
    bool approved,
    bytes32 seed
  ) external {
    RequireUtils utils = new RequireUtils();
    MockERC1155 token = new MockERC1155();

    vm.assume(tokenIds.length > 0);
    vm.assume(tokenIds.length <= 5);

    uint256[] memory minBalances = new uint256[](tokenIds.length);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 bal = uint256(keccak256(abi.encodePacked(seed, i))) % 1_000_000;
      token.mint(address(wallet), tokenIds[i], bal);
      minBalances[i] = token.balanceOf(address(wallet), tokenIds[i]);
    }

    token.setApprovedForAll(address(wallet), operator, approved);

    bool expectedSuccess = true;
    bytes memory expectedData;

    if (!approved) {
      expectedSuccess = false;
      expectedData =
        abi.encodeWithSelector(RequireUtils.ERC1155NotApproved.selector, address(token), address(wallet), operator);
    }

    (bool success, bytes memory result) = wallet.delegateCall(
      address(utils),
      abi.encodeWithSelector(
        RequireUtils.requireMinERC1155BalanceApprovalBatchSelf.selector, address(token), tokenIds, minBalances, operator
      )
    );
    assertEq(success, expectedSuccess);
    assertEq(result, expectedData);
  }
}

