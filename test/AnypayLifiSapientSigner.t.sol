// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {AnypayLifiSapientSigner} from "src/AnypayLifiSapientSigner.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {AnypayLiFiDecoder} from "src/libraries/AnypayLiFiDecoder.sol";
import {AnypayLiFiInterpreter, AnypayLifiInfo} from "src/libraries/AnypayLiFiInterpreter.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// Mock LiFi Diamond contract to receive calls
contract MockLiFiDiamond {
    event MockBridgeOnlyCalled(ILiFi.BridgeData bridgeData);
    event MockSwapAndBridgeCalled(ILiFi.BridgeData bridgeData, LibSwap.SwapData[] swapData);

    function mockLifiBridgeOnly(ILiFi.BridgeData calldata _bridgeData, bytes calldata _mockData) external {
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

contract AnypayLifiSapientSignerTest is Test {
    using Payload for Payload.Decoded;

    AnypayLifiSapientSigner public signerContract;
    MockLiFiDiamond public mockLiFiDiamond;
    address public userWalletAddress;
    uint256 public userSignerPrivateKey;
    address public userSignerAddress;

    // Sample data for BridgeData and SwapData
    ILiFi.BridgeData internal mockBridgeData = ILiFi.BridgeData({
        transactionId: bytes32(uint256(123)),
        bridge: "mockBridge",
        integrator: "Anypay",
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
        // The AnypayLifiSapientSigner is configured with the address of the LiFi diamond it will interact with.
        signerContract = new AnypayLifiSapientSigner(address(mockLiFiDiamond));

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
        Payload.Decoded memory payload = Payload.Decoded({
            kind: Payload.KIND_TRANSACTIONS,
            noChainId: false,
            calls: calls,
            space: 0,
            nonce: 1,
            message: "",
            imageHash: bytes32(0),
            digest: bytes32(0),
            parentWallets: new address[](0)
        });

        // 4. Generate the EIP-712 digest.
        bytes32 digestToSign = payload.hashFor(address(0));

        AnypayLifiInfo[] memory expectedLifiInfos = new AnypayLifiInfo[](1);
        expectedLifiInfos[0] = AnypayLiFiInterpreter.getOriginSwapInfo(mockBridgeData, mockSwapData);

        // 6. Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 7. Encode LifiInfos and ECDSA signature together
        bytes memory combinedSignature = abi.encode(expectedLifiInfos, ecdsaSignature);

        // 8. Manually derive the expected lifiIntentHash
        bytes32 expectedLifiIntentHash =
            AnypayLiFiInterpreter.getAnypayLifiInfoHash(expectedLifiInfos, userSignerAddress);

        // 9. Call recoverSapientSignature
        bytes32 actualLifiIntentHash = signerContract.recoverSapientSignature(payload, combinedSignature);

        // 10. Assert equality
        assertEq(actualLifiIntentHash, expectedLifiIntentHash, "Recovered LiFi intent hash mismatch");
    }

    function test_RecoverSingleLifiCall_BridgeOnly_ValidSignature() public {
        // 1. Prepare the BridgeData for a bridge-only call
        ILiFi.BridgeData memory bridgeOnlyData = ILiFi.BridgeData({
            transactionId: bytes32(uint256(456)),
            bridge: "mockBridgeOnly",
            integrator: "Anypay",
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
        Payload.Decoded memory payload = Payload.Decoded({
            kind: Payload.KIND_TRANSACTIONS,
            noChainId: false,
            calls: calls,
            space: 0,
            nonce: 2,
            message: "",
            imageHash: bytes32(0),
            digest: bytes32(0),
            parentWallets: new address[](0)
        });

        // 5. Generate the EIP-712 digest.
        bytes32 digestToSign = payload.hashFor(address(0));

        // 6. Prepare LifiInfos for encoding
        AnypayLifiInfo[] memory expectedLifiInfos = new AnypayLifiInfo[](1);
        expectedLifiInfos[0] = AnypayLiFiInterpreter.getOriginSwapInfo(bridgeOnlyData, emptySwapData);

        // 7. Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 8. Encode LifiInfos and ECDSA signature together
        bytes memory combinedSignature = abi.encode(expectedLifiInfos, ecdsaSignature);

        // 9. Manually derive the expected lifiIntentHash
        bytes32 expectedLifiIntentHash =
            AnypayLiFiInterpreter.getAnypayLifiInfoHash(expectedLifiInfos, userSignerAddress);

        // 10. Call recoverSapientSignature
        bytes32 actualLifiIntentHash = signerContract.recoverSapientSignature(payload, combinedSignature);

        // 11. Assert equality
        assertEq(
            actualLifiIntentHash, expectedLifiIntentHash, "Recovered LiFi intent hash mismatch for bridge-only call"
        );
    }

    // Helper to construct Payload.Decoded more easily if needed later
    function _createPayload(Payload.Call[] memory _calls, uint256 _nonce, bool _noChainId)
        internal
        view
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
}
