// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {AnypayLifiModifierWrapper} from "src/AnypayLifiModifierWrapper.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";

struct StargateSendParam {
    uint16 dstEid;
    bytes32 to;
    uint256 amountLD;
    uint256 minAmountLD;
    bytes extraOptions;
    bytes composeMsg;
    bytes oftCmd;
}

struct StargateMessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

struct StargateData {
    uint16 assetId;
    StargateSendParam sendParams;
    StargateMessagingFee fee;
    address payable refundAddress;
}

contract MockStargateFacetV2 {
    event StartBridgeCalled(bytes32 indexed transactionId, address receiver);
    event SwapAndStartBridgeCalled(bytes32 indexed transactionId, address receiver);

    function mockStartBridge(ILiFi.BridgeData calldata _bridgeData, StargateData calldata _stargateData)
        external
        payable
    {
        console.log("MockStargateFacetV2::mockStartBridge received receiver:", _bridgeData.receiver);
        emit StartBridgeCalled(_bridgeData.transactionId, _bridgeData.receiver);
    }

    function mockSwapAndStartBridge(
        ILiFi.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        StargateData calldata _stargateData
    ) external payable {
        console.log("MockStargateFacetV2::mockSwapAndStartBridge received receiver:", _bridgeData.receiver);
        emit SwapAndStartBridgeCalled(_bridgeData.transactionId, _bridgeData.receiver);
    }
}

contract StargateFacetV2WrapperTest is Test {
    AnypayLifiModifierWrapper public wrapper;
    MockStargateFacetV2 public mockFacet;
    address public user = makeAddr("user");
    address public originalReceiver = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

    ILiFi.BridgeData internal baseBridgeData = ILiFi.BridgeData({
        transactionId: bytes32(uint256(1)),
        bridge: "stargate",
        integrator: "testWrap",
        referrer: address(0),
        sendingAssetId: address(0x111111111117dC0aa78b770fA6A738034120C302),
        receiver: originalReceiver,
        minAmount: 1 ether,
        destinationChainId: 101,
        hasSourceSwaps: false,
        hasDestinationCall: false
    });

    StargateData internal baseStargateData = StargateData({
        assetId: 1,
        sendParams: StargateSendParam({
            dstEid: 30101,
            to: bytes32(uint256(uint160(originalReceiver))),
            amountLD: 1 ether,
            minAmountLD: 0.99 ether,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        }),
        fee: StargateMessagingFee({nativeFee: 0.01 ether, lzTokenFee: 0}),
        refundAddress: payable(user)
    });

    function setUp() public {
        mockFacet = new MockStargateFacetV2();
        wrapper = new AnypayLifiModifierWrapper(address(mockFacet));
        deal(user, 10 ether);
    }

    function test_StartBridge_CalldataParam_ReceivesModifiedReceiver() public {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        StargateData memory stargateData = baseStargateData;
        bridgeData.transactionId = bytes32(uint256(0x57A26A7E1));
        bridgeData.hasSourceSwaps = false;
        stargateData.sendParams.to = bytes32(uint256(uint160(originalReceiver)));

        bytes memory callData = abi.encodeCall(mockFacet.mockStartBridge, (bridgeData, stargateData));

        bytes4 expectedSelector = mockFacet.mockStartBridge.selector;
        vm.expectEmit(true, true, true, true, address(wrapper));
        emit AnypayLifiModifierWrapper.ForwardAttempt(228, expectedSelector, user, true);
        vm.expectEmit(true, true, false, true, address(mockFacet));
        emit MockStargateFacetV2.StartBridgeCalled(bridgeData.transactionId, user);

        vm.prank(user);
        (bool success,) = address(wrapper).call{value: stargateData.fee.nativeFee}(callData);

        // Assert
        assertTrue(success, "Call failed for startBridge (calldata)");
        console.log("startBridge (calldata) succeeded with MODIFIED receiver.");
    }

    function test_SwapAndStartBridge_MemoryParam_ReceivesModifiedReceiver() public {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        StargateData memory stargateData = baseStargateData;
        bridgeData.transactionId = bytes32(uint256(0x57A26A7E2));
        bridgeData.hasSourceSwaps = true;
        stargateData.sendParams.to = bytes32(uint256(uint160(originalReceiver)));

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

        bytes memory callData = abi.encodeCall(mockFacet.mockSwapAndStartBridge, (bridgeData, swapData, stargateData));

        bytes4 expectedSelector = mockFacet.mockSwapAndStartBridge.selector;
        vm.expectEmit(true, true, true, true, address(wrapper));
        emit AnypayLifiModifierWrapper.ForwardAttempt(228, expectedSelector, user, false);
        vm.expectEmit(true, true, true, true, address(wrapper));
        emit AnypayLifiModifierWrapper.ForwardAttempt(260, expectedSelector, user, true);
        vm.expectEmit(true, true, false, true, address(mockFacet));
        emit MockStargateFacetV2.SwapAndStartBridgeCalled(bridgeData.transactionId, user);

        vm.prank(user);
        (bool success,) = address(wrapper).call{value: stargateData.fee.nativeFee}(callData);

        assertTrue(success, "Call failed for swapAndStartBridge (memory)");
        console.log("swapAndStartBridge (memory) succeeded with MODIFIED receiver.");
    }
}
