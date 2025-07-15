// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract MockRevertingContract {
    fallback() external payable {
        revert("Always fails");
    }
}
