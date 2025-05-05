// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {AnypayLifiModifierWrapper} from "src/AnypayLifiModifierWrapper.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";

struct AcrossV3Data {
    address receiverAddress;
    address refundAddress;
    address receivingAssetId;
    uint256 outputAmount;
    uint64 outputAmountPercent;
    address exclusiveRelayer;
    uint32 quoteTimestamp;
    uint32 fillDeadline;
    uint32 exclusivityDeadline;
    bytes message;
}

contract MockAcrossFacetV3 {
    event StartBridgeCalled(bytes32 indexed transactionId, address receiver);
    event SwapAndStartBridgeCalled(bytes32 indexed transactionId, address receiver);
    event CallReverted(bytes4 selector, bytes reason);

    // Mocks `startBridgeTokensViaAcrossV3`
    function mockStartBridge(ILiFi.BridgeData memory _bridgeData, AcrossV3Data calldata _acrossData) external payable {
        console.log("MockAcrossFacetV3::mockStartBridge received receiver:", _bridgeData.receiver);
        emit StartBridgeCalled(_bridgeData.transactionId, _bridgeData.receiver);
    }

    // Mocks `swapAndStartBridgeTokensViaAcrossV3`
    function mockSwapAndStartBridge(
        ILiFi.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        AcrossV3Data calldata _acrossData
    ) external payable {
        console.log("MockAcrossFacetV3::mockSwapAndStartBridge received receiver:", _bridgeData.receiver);
        emit SwapAndStartBridgeCalled(_bridgeData.transactionId, _bridgeData.receiver);
    }

    receive() external payable {}
}

contract AcrossFacetV3WrapperTest is Test {
    AnypayLifiModifierWrapper public wrapper;
    MockAcrossFacetV3 public mockFacet;
    address public user = makeAddr("user");
    address public originalReceiver = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

    ILiFi.BridgeData internal baseBridgeData = ILiFi.BridgeData({
        transactionId: bytes32(uint256(1)),
        bridge: "across",
        integrator: "testWrap",
        referrer: address(0),
        sendingAssetId: address(0x111111111117dC0aa78b770fA6A738034120C302),
        receiver: originalReceiver,
        minAmount: 1 ether,
        destinationChainId: 10,
        hasSourceSwaps: false,
        hasDestinationCall: false
    });

    AcrossV3Data internal baseAcrossData = AcrossV3Data({
        receiverAddress: originalReceiver,
        refundAddress: user,
        receivingAssetId: address(0x022222222227dc0AA78b770fa6a738034120C302),
        outputAmount: 0.99 ether,
        outputAmountPercent: 0.99e18,
        exclusiveRelayer: address(0),
        quoteTimestamp: uint32(block.timestamp),
        fillDeadline: uint32(block.timestamp + 1 hours),
        exclusivityDeadline: uint32(block.timestamp + 30 minutes),
        message: ""
    });

    function setUp() public {
        mockFacet = new MockAcrossFacetV3();
        wrapper = new AnypayLifiModifierWrapper(address(mockFacet));
        deal(user, 10 ether);
    }

    function test_StartBridge_MemoryParam_FailsOrKeepsOriginalReceiver() public {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        AcrossV3Data memory acrossData = baseAcrossData;
        bridgeData.transactionId = bytes32(uint256(0xAC20551));

        bytes memory callData = abi.encodeCall(mockFacet.mockStartBridge, (bridgeData, acrossData));

        bytes4 expectedSelector = mockFacet.mockStartBridge.selector;
        vm.expectEmit(true, true, true, true, address(wrapper));
        emit AnypayLifiModifierWrapper.ForwardAttempt(228, expectedSelector, user, true);
        vm.expectEmit(true, true, false, true, address(mockFacet));
        emit MockAcrossFacetV3.StartBridgeCalled(bridgeData.transactionId, user);

        vm.prank(user);
        (bool success, bytes memory returnData) = address(wrapper).call{value: 0}(callData);

        assertTrue(success, "Call to wrapper failed unexpectedly.");
        console.log("Call succeeded and mock facet emitted event with MODIFIED receiver.");
    }

    function test_SwapAndStartBridge_MemoryParam_ReceivesModifiedReceiver() public {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        AcrossV3Data memory acrossData = baseAcrossData;
        bridgeData.transactionId = bytes32(uint256(0xAC20552));
        bridgeData.hasSourceSwaps = true;

        LibSwap.SwapData[] memory swapData = new LibSwap.SwapData[](1);
        swapData[0] = LibSwap.SwapData({
            callTo: address(0xdead),
            approveTo: address(0xdead),
            sendingAssetId: bridgeData.sendingAssetId,
            receivingAssetId: bridgeData.sendingAssetId,
            fromAmount: bridgeData.minAmount,
            callData: hex"",
            requiresDeposit: false
        });

        bytes memory callData = abi.encodeCall(mockFacet.mockSwapAndStartBridge, (bridgeData, swapData, acrossData));

        bytes4 expectedSelector = mockFacet.mockSwapAndStartBridge.selector;
        vm.expectEmit(true, true, true, true, address(wrapper));
        emit AnypayLifiModifierWrapper.ForwardAttempt(228, expectedSelector, user, false);
        vm.expectEmit(true, true, true, true, address(wrapper));
        emit AnypayLifiModifierWrapper.ForwardAttempt(260, expectedSelector, user, true);
        vm.expectEmit(true, true, false, true, address(mockFacet));
        emit MockAcrossFacetV3.SwapAndStartBridgeCalled(bridgeData.transactionId, user);

        vm.prank(user);
        (bool success, bytes memory returnData) = address(wrapper).call{value: 0}(callData);

        assertTrue(success, "Call to wrapper failed unexpectedly.");
        console.log("Call succeeded and mock facet emitted event with MODIFIED receiver.");
    }
}
