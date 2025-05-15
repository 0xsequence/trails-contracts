// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";

error EmptyLibSwapData();

struct AnypayLifiInfo {
    address originToken;
    uint256 minAmount;
    uint256 originChainId;
    uint256 destinationChainId;
}

/**
 * @title AnypayLifiInterpreter
 * @author Shun Kakinoki
 * @notice Library for interpreting LiFi data into AnypayLifiInfo structs.
 */
library AnypayLifiInterpreter {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error EmptyLibSwapData();

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

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
            originChainId: block.chainid,
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
