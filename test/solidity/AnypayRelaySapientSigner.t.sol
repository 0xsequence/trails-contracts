// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {AnypayRelaySapientSigner} from "src/AnypayRelaySapientSigner.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {AnypayRelayInfo} from "src/interfaces/AnypayRelay.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

// Mock RelayFacet contract to receive calls
contract MockRelayFacet {
    struct RelayData {
        bytes32 requestId;
        bytes32 nonEVMReceiver;
        bytes32 receivingAssetId;
        bytes signature;
    }

    event MockBridgeOnlyCalled(ILiFi.BridgeData bridgeData, RelayData relayData);
    event MockSwapAndBridgeCalled(ILiFi.BridgeData bridgeData, LibSwap.SwapData[] swapData, RelayData relayData);

    function startBridgeTokensViaRelay(ILiFi.BridgeData calldata _bridgeData, RelayData calldata _relayData) external {
        emit MockBridgeOnlyCalled(_bridgeData, _relayData);
    }

    function swapAndStartBridgeTokensViaRelay(
        ILiFi.BridgeData calldata _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        RelayData calldata _relayData
    ) external {
        emit MockSwapAndBridgeCalled(_bridgeData, _swapData, _relayData);
    }

    receive() external payable {}
    fallback() external payable {}
}

contract AnypayRelaySapientSignerTest is Test {
    using Payload for Payload.Decoded;
    using ECDSA for bytes32;

    AnypayRelaySapientSigner public signerContract;
    MockRelayFacet public mockRelayFacet;
    address public userWalletAddress;
    uint256 public userSignerPrivateKey;
    address public userSignerAddress;
    uint256 public relaySolverPrivateKey;
    address public relaySolverAddress;

    // Sample data
    ILiFi.BridgeData internal mockBridgeData;
    LibSwap.SwapData[] internal mockSwapData;
    MockRelayFacet.RelayData internal mockRelayData;

    function setUp() public {
        relaySolverPrivateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        relaySolverAddress = vm.addr(relaySolverPrivateKey);

        mockRelayFacet = new MockRelayFacet();
        signerContract = new AnypayRelaySapientSigner(relaySolverAddress);

        userSignerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        userSignerAddress = vm.addr(userSignerPrivateKey);
        userWalletAddress = makeAddr("userWallet");

        mockBridgeData = ILiFi.BridgeData({
            transactionId: bytes32(uint256(123)),
            bridge: "mockBridge",
            integrator: "Anypay",
            referrer: address(0),
            sendingAssetId: address(0x111111111117dC0aa78b770fA6A738034120C302),
            receiver: userSignerAddress,
            minAmount: 1 ether,
            destinationChainId: 10,
            hasSourceSwaps: true,
            hasDestinationCall: false
        });

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

        mockRelayData = MockRelayFacet.RelayData({
            requestId: bytes32(uint256(789)),
            nonEVMReceiver: bytes32(0),
            receivingAssetId: bytes32(uint256(uint160(mockBridgeData.sendingAssetId))),
            signature: bytes("") // Will be signed in tests
        });
    }

    function test_Recover_SwapAndBridge_ValidSignature() public {
        // 1. Prepare call data
        bytes memory callDataToRelayFacet =
            abi.encodeCall(mockRelayFacet.swapAndStartBridgeTokensViaRelay, (mockBridgeData, mockSwapData, mockRelayData));

        // 2. Create payload
        Payload.Decoded memory payload = _createPayload(callDataToRelayFacet, 1);

        // 3. Create attested relay info
        AnypayRelayInfo[] memory attestedRelayInfos = _createAttestedRelayInfos(payload.calls[0].to);

        // 4. Sign the relay data with the relay solver
        bytes memory signedRelaySignature = _signRelayData(attestedRelayInfos[0]);
        attestedRelayInfos[0].signature = signedRelaySignature;
        // Also update mockRelayData for the actual call
        mockRelayData.signature = signedRelaySignature;
        callDataToRelayFacet = abi.encodeCall(
            mockRelayFacet.swapAndStartBridgeTokensViaRelay, (mockBridgeData, mockSwapData, mockRelayData)
        );
        payload.calls[0].data = callDataToRelayFacet;

        // 5. Sign the payload digest with the user signer
        bytes32 digestToSign = keccak256(abi.encode(payload.hashFor(address(0))));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 6. Encode the combined signature
        bytes memory combinedSignature = abi.encode(attestedRelayInfos, ecdsaSignature, userSignerAddress);

        // 7. Derive expected intent hash
        bytes32 expectedIntentHash = keccak256(abi.encode(attestedRelayInfos, userSignerAddress));

        // 8. Call recoverSapientSignature
        bytes32 actualIntentHash = signerContract.recoverSapientSignature(payload, combinedSignature);

        // 9. Assert equality
        assertEq(actualIntentHash, expectedIntentHash, "Recovered relay intent hash mismatch");
    }

    function test_Recover_BridgeOnly_ValidSignature() public {
        // 1. Prepare call data
        mockBridgeData.hasSourceSwaps = false;
        bytes memory callDataToRelayFacet =
            abi.encodeCall(mockRelayFacet.startBridgeTokensViaRelay, (mockBridgeData, mockRelayData));

        // 2. Create payload
        Payload.Decoded memory payload = _createPayload(callDataToRelayFacet, 2);

        // 3. Create attested relay info
        AnypayRelayInfo[] memory attestedRelayInfos = _createAttestedRelayInfos(payload.calls[0].to);

        // 4. Sign relay data
        bytes memory signedRelaySignature = _signRelayData(attestedRelayInfos[0]);
        attestedRelayInfos[0].signature = signedRelaySignature;
        mockRelayData.signature = signedRelaySignature;
        callDataToRelayFacet = abi.encodeCall(mockRelayFacet.startBridgeTokensViaRelay, (mockBridgeData, mockRelayData));
        payload.calls[0].data = callDataToRelayFacet;

        // 5. Sign payload digest
        bytes32 digestToSign = keccak256(abi.encode(payload.hashFor(address(0))));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 6. Encode combined signature
        bytes memory combinedSignature = abi.encode(attestedRelayInfos, ecdsaSignature, userSignerAddress);

        // 7. Get expected hash
        bytes32 expectedIntentHash = keccak256(abi.encode(attestedRelayInfos, userSignerAddress));

        // 8. Recover signature
        bytes32 actualIntentHash = signerContract.recoverSapientSignature(payload, combinedSignature);

        // 9. Assert
        assertEq(actualIntentHash, expectedIntentHash, "Recovered relay intent hash mismatch for bridge-only");
    }

    function test_Recover_InvalidRelayQuote_Reverts() public {
        // 1. Prepare call data
        bytes memory callDataToRelayFacet =
            abi.encodeCall(mockRelayFacet.swapAndStartBridgeTokensViaRelay, (mockBridgeData, mockSwapData, mockRelayData));

        // 2. Create payload
        Payload.Decoded memory payload = _createPayload(callDataToRelayFacet, 3);

        // 3. Create attested relay info
        AnypayRelayInfo[] memory attestedRelayInfos = _createAttestedRelayInfos(payload.calls[0].to);

        // 4. Sign with a *different* key
        uint256 badPrivateKey = 0xdeadbeef;
        bytes32 message = _getRelayMessageHash(attestedRelayInfos[0]);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(badPrivateKey, message);
        bytes memory badSignature = abi.encodePacked(r, s, v);

        attestedRelayInfos[0].signature = badSignature;
        mockRelayData.signature = badSignature; // Update mock data for the call
        callDataToRelayFacet = abi.encodeCall(
            mockRelayFacet.swapAndStartBridgeTokensViaRelay, (mockBridgeData, mockSwapData, mockRelayData)
        );
        payload.calls[0].data = callDataToRelayFacet;

        // 5. Sign payload digest
        bytes32 digestToSign = keccak256(abi.encode(payload.hashFor(address(0))));
        (v, r, s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 6. Encode combined signature
        bytes memory combinedSignature = abi.encode(attestedRelayInfos, ecdsaSignature, userSignerAddress);

        // 7. Expect revert
        vm.expectRevert(AnypayRelaySapientSigner.InvalidRelayQuote.selector);
        signerContract.recoverSapientSignature(payload, combinedSignature);
    }

    function _createPayload(bytes memory callData, uint256 nonce) internal view returns (Payload.Decoded memory) {
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: address(mockRelayFacet),
            value: 0,
            data: callData,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
        });

        return Payload.Decoded({
            kind: Payload.KIND_TRANSACTIONS,
            noChainId: false,
            calls: calls,
            space: 0,
            nonce: nonce,
            message: "",
            imageHash: bytes32(0),
            digest: bytes32(0),
            parentWallets: new address[](0)
        });
    }

    function _createAttestedRelayInfos(address target) internal view returns (AnypayRelayInfo[] memory) {
        AnypayRelayInfo[] memory infos = new AnypayRelayInfo[](1);
        infos[0] = AnypayRelayInfo({
            requestId: mockRelayData.requestId,
            signature: bytes(""), // To be filled in later
            nonEVMReceiver: mockRelayData.nonEVMReceiver,
            receivingAssetId: mockRelayData.receivingAssetId,
            sendingAssetId: mockBridgeData.sendingAssetId,
            receiver: mockBridgeData.receiver,
            destinationChainId: mockBridgeData.destinationChainId,
            minAmount: mockBridgeData.minAmount,
            target: target
        });
        return infos;
    }

    function _signRelayData(AnypayRelayInfo memory info) internal returns (bytes memory) {
        bytes32 messageHash = _getRelayMessageHash(info);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relaySolverPrivateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    function _getRelayMessageHash(AnypayRelayInfo memory info) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                info.requestId,
                block.chainid,
                bytes32(uint256(uint160(info.target))),
                bytes32(uint256(uint160(info.sendingAssetId))),
                signerContract._getMappedChainId(info.destinationChainId),
                info.receiver == signerContract.NON_EVM_ADDRESS()
                    ? info.nonEVMReceiver
                    : bytes32(uint256(uint160(info.receiver))),
                info.receivingAssetId
            )
        );
    }
} 