// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {ILiFi} from "lifi-contracts/interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";

error EmptyLibSwapData();

struct AnypayLifiInfo {
    address originToken;
    uint256 minAmount;
    uint256 destinationChainId;
}

library AnypayLifiInterpreter {
    function getOriginSwapInfo(ILiFi.BridgeData memory bridgeData, LibSwap.SwapData[] memory swapData)
        internal
        pure
        returns (AnypayLifiInfo memory)
    {
        address originToken;
        uint256 minAmount;

        if (bridgeData.hasSourceSwaps) {
            if (swapData.length == 0) {
                revert EmptyLibSwapData();
            }
            originToken = swapData[0].sendingAssetId;
            minAmount = swapData[0].fromAmount;
        } else {
            originToken = bridgeData.sendingAssetId;
            minAmount = bridgeData.minAmount;
        }

        return AnypayLifiInfo({
            originToken: originToken,
            minAmount: minAmount,
            destinationChainId: bridgeData.destinationChainId
        });
    }

    function getAnypayLifiInfoHash(AnypayLifiInfo[] memory lifiInfos, address attestationAddress)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(lifiInfos, attestationAddress));
    }
}
