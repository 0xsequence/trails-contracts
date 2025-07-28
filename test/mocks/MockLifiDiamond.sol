// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract MockLifiDiamond {
    fallback() external payable {
        revert();
    }
}
