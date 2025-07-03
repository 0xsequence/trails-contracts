// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Test, console} from "forge-std/Test.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {TrailsLiFiSapientSigner} from "@/TrailsLiFiSapientSigner.sol";
import {TrailsExecutionInfoParams} from "@/libraries/TrailsExecutionInfoParams.sol";
import {TrailsExecutionInfoInterpreter, TrailsExecutionInfo} from "@/libraries/TrailsExecutionInfoInterpreter.sol";
import {TrailsDecodingStrategy} from "@/interfaces/TrailsLiFi.sol";
import {TrailsLiFiInterpreter} from "@/libraries/TrailsLiFiInterpreter.sol";

// Mock LiFi Diamond contract to receive calls
contract MockLiFiDiamond {
    event MockBridgeOnlyCalled(ILiFi.BridgeData bridgeData);
    event MockSwapAndBridgeCalled(ILiFi.BridgeData bridgeData, LibSwap.SwapData[] swapData);

    function mockLifiBridgeOnly(ILiFi.BridgeData calldata _bridgeData, bytes calldata /*_mockData*/ ) external {
        emit MockBridgeOnlyCalled(_bridgeData);
    }

    function mockLifiSwapAndBridge(ILiFi.BridgeData calldata _bridgeData, LibSwap.SwapData[] calldata _swapData)
        external
    {
        emit MockSwapAndBridgeCalled(_bridgeData, _swapData);
    }

    receive() external payable {}
    fallback() external payable {}
}

contract TrailsLiFiSapientSignerTest is Test {
    using Payload for Payload.Decoded;

    TrailsLiFiSapientSigner public signerContract;
    MockLiFiDiamond public mockLiFiDiamond;
    address public userWalletAddress;
    uint256 public userSignerPrivateKey;
    address public userSignerAddress;

    // Sample data for BridgeData and SwapData
    ILiFi.BridgeData internal mockBridgeData = ILiFi.BridgeData({
        transactionId: bytes32(uint256(123)),
        bridge: "mockBridge",
        integrator: "Trails",
        referrer: address(0),
        sendingAssetId: address(0x111111111117dC0aa78b770fA6A738034120C302),
        receiver: address(0xdeadbeef),
        minAmount: 1 ether,
        destinationChainId: 10,
        hasSourceSwaps: true,
        hasDestinationCall: false
    });

    LibSwap.SwapData[] internal mockSwapData; // Will be initialized in setUp or tests

    function setUp() public {
        mockLiFiDiamond = new MockLiFiDiamond();
        // The TrailsLiFiSapientSigner is configured with the address of the LiFi diamond it will interact with.
        signerContract = new TrailsLiFiSapientSigner(address(mockLiFiDiamond));

        userSignerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        userSignerAddress = vm.addr(userSignerPrivateKey);
        userWalletAddress = makeAddr("userWallet");

        // Initialize mockSwapData
        LibSwap.SwapData[] memory swaps = new LibSwap.SwapData[](1);
        swaps[0] = LibSwap.SwapData({
            callTo: address(0x222222222227dC0AA78B770FA6A738034120c302),
            approveTo: address(0x222222222227dC0AA78B770FA6A738034120c302),
            sendingAssetId: mockBridgeData.sendingAssetId,
            receivingAssetId: address(0x222222222227dC0AA78B770FA6A738034120c302),
            fromAmount: mockBridgeData.minAmount,
            callData: hex"1234",
            requiresDeposit: true
        });
        mockSwapData = swaps;
    }

    function test_RecoverSingleLifiCall_ValidSignature() public {
        // 1. Prepare the call data for the mockLifiSwapAndBridge
        bytes memory callDataToLifiDiamond =
            abi.encodeCall(mockLiFiDiamond.mockLifiSwapAndBridge, (mockBridgeData, mockSwapData));

        // 2. Construct the Payload.Call
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: address(mockLiFiDiamond),
            value: 0,
            data: callDataToLifiDiamond,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
        });

        // 3. Construct the Payload.Decoded
        Payload.Decoded memory payload = _createPayload(calls, 1, false);

        // 4. Prepare LifiInfos for encoding
        TrailsExecutionInfo[] memory expectedLifiInfos = new TrailsExecutionInfo[](1);
        expectedLifiInfos[0] = TrailsLiFiInterpreter.getOriginSwapInfo(mockBridgeData, mockSwapData);

        // 5. Generate the EIP-712 digest.
        bytes32 digestToSign = payload.hashFor(address(0));
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digestToSign));

        // 6. Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digest);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 7. Encode LifiInfos, ECDSA signature, and strategy together
        bytes memory combinedSignature = abi.encode(
            expectedLifiInfos, TrailsDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE, ecdsaSignature, userSignerAddress
        );

        // 8. Manually derive the expected lifiIntentHash
        bytes32 expectedLifiIntentHash =
            TrailsExecutionInfoParams.getTrailsExecutionInfoHash(expectedLifiInfos, userSignerAddress);

        // 9. Call recoverSapientSignature
        vm.prank(userWalletAddress);
        bytes32 actualLifiIntentHash = signerContract.recoverSapientSignature(payload, combinedSignature);

        // 10. Assert equality
        assertEq(actualLifiIntentHash, expectedLifiIntentHash, "Recovered LiFi intent hash mismatch");
    }

    function test_RecoverSingleLifiCall_BridgeOnly_ValidSignature() public {
        // 1. Prepare the BridgeData for a bridge-only call
        ILiFi.BridgeData memory bridgeOnlyData = ILiFi.BridgeData({
            transactionId: bytes32(uint256(456)),
            bridge: "mockBridgeOnly",
            integrator: "Trails",
            referrer: address(0),
            sendingAssetId: address(0x111111111117dC0aa78b770fA6A738034120C302),
            receiver: address(0xbeefdead),
            minAmount: 2 ether,
            destinationChainId: 1,
            hasSourceSwaps: false,
            hasDestinationCall: false
        });

        LibSwap.SwapData[] memory emptySwapData = new LibSwap.SwapData[](0);

        // 2. Prepare the call data for the mockLifiFunction
        bytes memory callDataToLifiDiamond =
            abi.encodeCall(mockLiFiDiamond.mockLifiBridgeOnly, (bridgeOnlyData, new bytes(0)));

        // 3. Construct the Payload.Call
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: address(mockLiFiDiamond),
            value: 0,
            data: callDataToLifiDiamond,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
        });

        // 4. Construct the Payload.Decoded
        Payload.Decoded memory payload = _createPayload(calls, 2, false);

        // 5. Generate the EIP-712 digest.
        bytes32 digestToSign = payload.hashFor(address(0));

        // 6. Prepare LifiInfos for encoding
        TrailsExecutionInfo[] memory expectedLifiInfos = new TrailsExecutionInfo[](1);
        expectedLifiInfos[0] = TrailsLiFiInterpreter.getOriginSwapInfo(bridgeOnlyData, emptySwapData);

        // 7. Sign the digest
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digestToSign));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digest);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 8. Encode LifiInfos, ECDSA signature, and strategy together
        bytes memory combinedSignature =
            abi.encode(expectedLifiInfos, TrailsDecodingStrategy.SINGLE_BRIDGE_DATA, ecdsaSignature, userSignerAddress);

        // 9. Manually derive the expected lifiIntentHash
        bytes32 expectedLifiIntentHash =
            TrailsExecutionInfoParams.getTrailsExecutionInfoHash(expectedLifiInfos, userSignerAddress);

        // 10. Call recoverSapientSignature
        vm.prank(userWalletAddress);
        bytes32 actualLifiIntentHash = signerContract.recoverSapientSignature(payload, combinedSignature);

        // 11. Assert equality
        assertEq(
            actualLifiIntentHash, expectedLifiIntentHash, "Recovered LiFi intent hash mismatch for bridge-only call"
        );
    }

    // Helper to construct Payload.Decoded more easily if needed later
    function _createPayload(Payload.Call[] memory _calls, uint256 _nonce, bool _noChainId)
        internal
        pure
        returns (Payload.Decoded memory)
    {
        return Payload.Decoded({
            kind: Payload.KIND_TRANSACTIONS,
            noChainId: _noChainId,
            calls: _calls,
            space: 0,
            nonce: _nonce,
            message: "",
            imageHash: bytes32(0),
            digest: bytes32(0),
            parentWallets: new address[](0)
        });
    }

    // function test_DecodeSignature_ArbitraryBytes() public {
    //     // 1. Construct the Payload.Decoded from the provided JSON structure
    //     Payload.Decoded memory payload;
    //     payload.kind = Payload.KIND_TRANSACTIONS;
    //     payload.noChainId = false;

    //     payload.calls = new Payload.Call[](1);
    //     payload.calls[0] = Payload.Call({
    //         to: address(0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE),
    //         value: 138741597760998,
    //         data: hex"ae328590000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000002001a6c9a90f454284e687201489f60c8c1a3612e9c83ab4d08daf111ebd45ae29d000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000056ac23af2475c220f49698950000b83dabe0e6fc00000000000000000000000000000000000000000000000000007e2f4ba66de6000000000000000000000000000000000000000000000000000000000000210500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000572656c617900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000086c6966692d61706900000000000000000000000000000000000000000000000056147d980032a0c0a2486db507e23a6314155ad27b5c835a01f262e5b82b26a800000000000000000000000056ac23af2475c220f49698950000b83dabe0e6fc000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda0291300000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000041754a6a5d9649c6b8131ec1b2b2725ada10fee1c42b6e40b1592ea102d2bc62e11c4b92d038b238c0220babc2a1394c2aecdec1d92d516693b7af43e2adb8cc751b00000000000000000000000000000000000000000000000000000000000000",
    //         gasLimit: 0,
    //         delegateCall: false,
    //         onlyFallback: false,
    //         behaviorOnError: 0
    //     });
    //     payload.space = 0;
    //     payload.nonce = 0;
    //     payload.message = bytes("");
    //     payload.imageHash = bytes32(0);
    //     payload.digest = bytes32(0);
    //     payload.parentWallets = new address[](0);

    //     // 2. Define and decode arbitraryBytes to get the signature
    //     bytes memory arbitraryBytes =
    //         hex"000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000028a93877b0d458000000000000000000000000000000000000000000000000000000000000a4b1000000000000000000000000000000000000000000000000000000000000210500000000000000000000000000000000000000000000000000000000000000413534d25dc48a1b07cc11930f74d8070044c1dbedb0486be75007608393c11ae53ac288d1de18a25190aa048537f9050d1b46e0d8b64b5b36ce370f1a0c7fda853700000000000000000000000000000000000000000000000000000000000000";

    //     (TrailsExecutionInfo[] memory lifiInfos, bytes memory actualAttestationSignature) =
    //         signerContract.decodeSignature(arbitraryBytes);

    //     assertEq(lifiInfos.length, 1, "Decoded LiFi Infos length mismatch");
    //     assertEq(actualAttestationSignature.length, 65, "Decoded signature length mismatch");

    //     bytes32 digestToSign = keccak256(abi.encode(payload.hashFor(address(0))));

    //     address recoveredSigner = ECDSA.recover(digestToSign, actualAttestationSignature);

    //     assertEq(recoveredSigner, userSignerAddress, "Recovered signer mismatch. The signature from arbitraryBytes does not match the provided payload.");
    // }
}
