// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// -----------------------------------------------------------------------------
// Mock Contract
// -----------------------------------------------------------------------------

contract MockSenderGetter {
    function getSender() external view returns (address) {
        return msg.sender;
    }
}
