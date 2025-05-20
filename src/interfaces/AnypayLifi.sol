// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

struct AnypayLifiInfo {
    address originToken;
    uint256 amount;
    uint256 originChainId;
    uint256 destinationChainId;
}
