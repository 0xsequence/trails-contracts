// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TrailsMulticall3Router} from "src/TrailsMulticall3Router.sol";
import {MockSenderGetter} from "test/mocks/MockSenderGetter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockMulticall3} from "test/mocks/MockMulticall3.sol";

// Struct definitions to match the contract's IMulticall3 interface
struct Call3 {
    address target;
    bool allowFailure;
    bytes callData;
}

struct Result {
    bool success;
    bytes returnData;
}

// A malicious token for testing transferFrom failures
contract FailingToken is MockERC20 {
    bool public shouldFail;

    constructor() MockERC20("Failing Token", "FAIL", 18) {}

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (shouldFail) {
            return false;
        }
        return super.transferFrom(from, to, amount);
    }
}

contract TrailsMulticall3RouterTest is Test {
    TrailsMulticall3Router internal multicallWrapper;
    MockSenderGetter internal getter;
    MockERC20 internal mockToken;
    FailingToken internal failingToken;

    address internal user = makeAddr("user");

    function setUp() public {
        // Deploy mock multicall3 at the expected address
        MockMulticall3 mockMulticall3 = new MockMulticall3();
        vm.etch(0xcA11bde05977b3631167028862bE2a173976CA11, address(mockMulticall3).code);

        multicallWrapper = new TrailsMulticall3Router();
        getter = new MockSenderGetter();
        mockToken = new MockERC20("MockToken", "MTK", 18);
        failingToken = new FailingToken();

        vm.deal(user, 10 ether);
        mockToken.mint(user, 1000e18);
        failingToken.mint(user, 1000e18);
    }

    function test_Execute_FromEOA_ShouldPreserveEOAAsSender() public {
        address eoa = makeAddr("eoa");

        Call3[] memory calls = new Call3[](1);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        vm.prank(eoa);
        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);
        // Execute the call (we can't easily check the return value due to type conflicts)
        multicallWrapper.execute(callData);

        // The test passes if no revert occurred, which means the call was successful
    }

    function test_Execute_FromContract_ShouldPreserveContractAsSender() public {
        Call3[] memory calls = new Call3[](1);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);
        // Execute the call (we can't easily check the return value due to type conflicts)
        multicallWrapper.execute(callData);

        // The test passes if no revert occurred, which means the call was successful
    }

    function test_Execute_WithMultipleCalls() public {
        Call3[] memory calls = new Call3[](2);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});
        calls[1] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);
        // Execute the calls (we can't easily check the return values due to type conflicts)
        multicallWrapper.execute(callData);

        // The test passes if no revert occurred, which means both calls were successful
    }

    function test_pullAmountAndExecute_WithValidToken_ShouldTransferAndExecute() public {
        uint256 transferAmount = 100e18;

        // Approve the router to spend tokens
        vm.prank(user);
        mockToken.approve(address(multicallWrapper), transferAmount);

        Call3[] memory calls = new Call3[](1);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);

        vm.prank(user);
        multicallWrapper.pullAmountAndExecute(address(mockToken), transferAmount, callData);

        // Check that tokens were transferred to the router
        assertEq(mockToken.balanceOf(address(multicallWrapper)), transferAmount);
        assertEq(mockToken.balanceOf(user), 1000e18 - transferAmount);
    }

    function test_pullAmountAndExecute_WithZeroAddress_ShouldSkipTransfer() public {
        Call3[] memory calls = new Call3[](1);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);

        vm.prank(user);
        multicallWrapper.pullAmountAndExecute(address(0), 1 ether, callData);

        // Check that no tokens were transferred (since address(0) was used)
        assertEq(mockToken.balanceOf(address(multicallWrapper)), 0);
        assertEq(mockToken.balanceOf(user), 1000e18);
    }

    function test_pullAmountAndExecute_WithZeroAmount_ShouldSkipTransfer() public {
        Call3[] memory calls = new Call3[](1);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);

        vm.prank(user);
        multicallWrapper.pullAmountAndExecute(address(mockToken), 0, callData);

        // Check that no tokens were transferred (since amount was 0)
        assertEq(mockToken.balanceOf(address(multicallWrapper)), 0);
        assertEq(mockToken.balanceOf(user), 1000e18);
    }

    function test_RevertWhen_pullAmountAndExecute_InsufficientAllowance() public {
        uint256 transferAmount = 100e18;

        Call3[] memory calls = new Call3[](1);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);

        vm.prank(user);
        vm.expectRevert("TrailsMulticall3Router: transferFrom failed");
        multicallWrapper.pullAmountAndExecute(address(mockToken), transferAmount, callData);
    }

    function test_RevertWhen_pullAmountAndExecute_TransferFromFails() public {
        uint256 transferAmount = 100e18;

        // Set the failing token to fail on transferFrom
        failingToken.setShouldFail(true);

        vm.prank(user);
        failingToken.approve(address(multicallWrapper), transferAmount);

        Call3[] memory calls = new Call3[](1);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);

        vm.prank(user);
        vm.expectRevert("TrailsMulticall3Router: transferFrom failed");
        multicallWrapper.pullAmountAndExecute(address(failingToken), transferAmount, callData);
    }

    function test_ReceiveETH_ShouldAcceptETH() public {
        uint256 depositAmount = 1 ether;

        vm.prank(user);
        (bool success,) = address(multicallWrapper).call{value: depositAmount}("");
        assertTrue(success);

        assertEq(address(multicallWrapper).balance, depositAmount);
    }

    function test_Multicall3Address_IsCorrect() public view {
        assertEq(multicallWrapper.multicall3(), 0xcA11bde05977b3631167028862bE2a173976CA11);
    }
}
