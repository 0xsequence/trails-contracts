// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {AnypayLiFiFlagDecoder} from "@/libraries/AnypayLiFiFlagDecoder.sol";
import {AnypayDecodingStrategy} from "@/interfaces/AnypayLiFi.sol";

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

contract AnypayDecoderTestHelperForStargate {
    using AnypayLiFiFlagDecoder for bytes;

    function mockDecodeLiFiDataOrRevert(bytes memory data, AnypayDecodingStrategy strategy)
        external
        pure
        returns (ILiFi.BridgeData memory finalBridgeData, LibSwap.SwapData[] memory finalSwapDataArray)
    {
        return data.decodeLiFiDataOrRevert(strategy);
    }
}

contract MockStargateFacetV2 {
    event StartBridgeCalled(bytes32 indexed transactionId, address receiver);
    event SwapAndStartBridgeCalled(bytes32 indexed transactionId, address receiver);

    function mockStartBridge(ILiFi.BridgeData calldata _bridgeData, StargateData calldata /*_stargateData*/)
        external
        payable
    {
        console.log("MockStargateFacetV2::mockStartBridge received receiver:", _bridgeData.receiver);
        emit StartBridgeCalled(_bridgeData.transactionId, _bridgeData.receiver);
    }

    function mockSwapAndStartBridge(
        ILiFi.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata /*_swapData*/,
        StargateData calldata /*_stargateData*/
    ) external payable {
        console.log("MockStargateFacetV2::mockSwapAndStartBridge received receiver:", _bridgeData.receiver);
        emit SwapAndStartBridgeCalled(_bridgeData.transactionId, _bridgeData.receiver);
    }
}

contract MockStargateFacetV2Test is Test {
    MockStargateFacetV2 public mockFacet;
    address public user = makeAddr("user");
    address public originalReceiver = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

    AnypayDecoderTestHelperForStargate public decoderHelper;

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
        decoderHelper = new AnypayDecoderTestHelperForStargate();
        deal(user, 10 ether);
    }

    function test_AnypayDecoder_TryDecode_MockStargate_StartBridge() public view {
        ILiFi.BridgeData memory bridgeDataInput = baseBridgeData;
        StargateData memory stargateDataInput = baseStargateData;
        bridgeDataInput.transactionId = bytes32(uint256(0xDEC0DE51)); // Unique ID for this test
        bridgeDataInput.hasSourceSwaps = false; // Explicitly set for this case

        bytes memory encodedCallForStargate =
            abi.encodeCall(mockFacet.mockStartBridge, (bridgeDataInput, stargateDataInput));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            decoderHelper.mockDecodeLiFiDataOrRevert(encodedCallForStargate, AnypayDecodingStrategy.SINGLE_BRIDGE_DATA);

        assertEq(
            decodedBridgeData.transactionId,
            bridgeDataInput.transactionId,
            "AD_STARGATE_01: Decoded BridgeData transactionId mismatch"
        );
        assertEq(decodedBridgeData.bridge, bridgeDataInput.bridge, "AD_STARGATE_01: Decoded BridgeData bridge mismatch");
        assertEq(
            decodedBridgeData.integrator,
            bridgeDataInput.integrator,
            "AD_STARGATE_01: Decoded BridgeData integrator mismatch"
        );
        assertEq(
            decodedBridgeData.receiver, bridgeDataInput.receiver, "AD_STARGATE_01: Decoded BridgeData receiver mismatch"
        );
        assertEq(
            decodedBridgeData.sendingAssetId,
            bridgeDataInput.sendingAssetId,
            "AD_STARGATE_01: Decoded BridgeData sendingAssetId mismatch"
        );
        assertEq(
            decodedBridgeData.minAmount,
            bridgeDataInput.minAmount,
            "AD_STARGATE_01: Decoded BridgeData minAmount mismatch"
        );
        assertEq(
            decodedBridgeData.destinationChainId,
            bridgeDataInput.destinationChainId,
            "AD_STARGATE_01: Decoded BridgeData destinationChainId mismatch"
        );
        assertFalse(
            decodedBridgeData.hasSourceSwaps, "AD_STARGATE_01: Decoded BridgeData hasSourceSwaps should be false"
        );
        assertEq(
            decodedSwapData.length, 0, "AD_STARGATE_01: Decoded SwapData array should be empty for mockStartBridge"
        );
    }

    function test_AnypayDecoder_TryDecode_MockStargate_SwapAndStartBridge() public view {
        ILiFi.BridgeData memory bridgeDataInput = baseBridgeData;
        StargateData memory stargateDataInput = baseStargateData;
        bridgeDataInput.transactionId = bytes32(uint256(0xDEC0DE52)); // Unique ID
        bridgeDataInput.hasSourceSwaps = true;

        LibSwap.SwapData[] memory swapDataInput = new LibSwap.SwapData[](1);
        swapDataInput[0] = LibSwap.SwapData({
            callTo: address(0xdeadbeef),
            approveTo: address(0xdeadbeef),
            sendingAssetId: bridgeDataInput.sendingAssetId,
            receivingAssetId: address(0xcafebabe),
            fromAmount: bridgeDataInput.minAmount,
            callData: hex"010203",
            requiresDeposit: true
        });

        bytes memory encodedCallForStargate =
            abi.encodeCall(mockFacet.mockSwapAndStartBridge, (bridgeDataInput, swapDataInput, stargateDataInput));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) = decoderHelper
            .mockDecodeLiFiDataOrRevert(encodedCallForStargate, AnypayDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);

        assertEq(
            decodedBridgeData.transactionId,
            bridgeDataInput.transactionId,
            "AD_STARGATE_02: Decoded BridgeData transactionId mismatch"
        );
        assertEq(decodedBridgeData.bridge, bridgeDataInput.bridge, "AD_STARGATE_02: Decoded BridgeData bridge mismatch");
        assertTrue(decodedBridgeData.hasSourceSwaps, "AD_STARGATE_02: Decoded BridgeData hasSourceSwaps should be true");

        assertEq(decodedSwapData.length, swapDataInput.length, "AD_STARGATE_02: Decoded SwapData array length mismatch");
        if (decodedSwapData.length > 0 && swapDataInput.length > 0) {
            assertEq(
                decodedSwapData[0].callTo,
                swapDataInput[0].callTo,
                "AD_STARGATE_02: Decoded SwapData[0].callTo mismatch"
            );
            assertEq(
                decodedSwapData[0].approveTo,
                swapDataInput[0].approveTo,
                "AD_STARGATE_02: Decoded SwapData[0].approveTo mismatch"
            );
            assertEq(
                decodedSwapData[0].sendingAssetId,
                swapDataInput[0].sendingAssetId,
                "AD_STARGATE_02: Decoded SwapData[0].sendingAssetId mismatch"
            );
            assertEq(
                decodedSwapData[0].receivingAssetId,
                swapDataInput[0].receivingAssetId,
                "AD_STARGATE_02: Decoded SwapData[0].receivingAssetId mismatch"
            );
            assertEq(
                decodedSwapData[0].fromAmount,
                swapDataInput[0].fromAmount,
                "AD_STARGATE_02: Decoded SwapData[0].fromAmount mismatch"
            );
            assertEq(
                decodedSwapData[0].callData,
                swapDataInput[0].callData,
                "AD_STARGATE_02: Decoded SwapData[0].callData mismatch"
            );
            assertEq(
                decodedSwapData[0].requiresDeposit,
                swapDataInput[0].requiresDeposit,
                "AD_STARGATE_02: Decoded SwapData[0].requiresDeposit mismatch"
            );
        }
    }

    function test_AnypayDecoder_DecodeOrRevert_MockStargate_SwapAndStartBridge() public view {
        ILiFi.BridgeData memory bridgeDataInput = baseBridgeData;
        StargateData memory stargateDataInput = baseStargateData;
        bridgeDataInput.transactionId = bytes32(uint256(0xDEC0DE53)); // Unique ID
        bridgeDataInput.hasSourceSwaps = true;

        LibSwap.SwapData[] memory swapDataInput = new LibSwap.SwapData[](1);
        swapDataInput[0] = LibSwap.SwapData({
            callTo: address(0x12345),
            approveTo: address(0x12345),
            sendingAssetId: bridgeDataInput.sendingAssetId,
            receivingAssetId: address(0x6789A),
            fromAmount: bridgeDataInput.minAmount,
            callData: hex"abcdef",
            requiresDeposit: false
        });

        bytes memory encodedCallForStargate =
            abi.encodeCall(mockFacet.mockSwapAndStartBridge, (bridgeDataInput, swapDataInput, stargateDataInput));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) = decoderHelper
            .mockDecodeLiFiDataOrRevert(encodedCallForStargate, AnypayDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);

        assertTrue(true, "AD_STARGATE_03: decodeLiFiDataOrRevert should succeed for mockSwapAndStartBridge calldata");

        assertEq(
            decodedBridgeData.transactionId,
            bridgeDataInput.transactionId,
            "AD_STARGATE_03: Decoded BridgeData transactionId mismatch"
        );
        assertTrue(decodedBridgeData.hasSourceSwaps, "AD_STARGATE_03: Decoded BridgeData hasSourceSwaps should be true");

        assertEq(decodedSwapData.length, swapDataInput.length, "AD_STARGATE_03: Decoded SwapData array length mismatch");
        if (decodedSwapData.length > 0 && swapDataInput.length > 0) {
            assertEq(
                decodedSwapData[0].callTo,
                swapDataInput[0].callTo,
                "AD_STARGATE_03: Decoded SwapData[0].callTo mismatch"
            );
            // Add more assertions for other fields in SwapData if necessary
        }
    }
}
