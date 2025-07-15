// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ITokenMessengerV2} from "@/interfaces/TrailsCCTPV2.sol";
import {TrailsCCTPV2Validator} from "@/libraries/TrailsCCTPV2Validator.sol";

contract MockTrailsCCTPV2Router {
    using TrailsCCTPV2Validator for bytes;

    address public tokenMessenger;

    error ExecutionFailed();

    constructor(address _tokenMessenger) {
        tokenMessenger = _tokenMessenger;
    }

    function execute(bytes calldata data) external payable {
        data.validate();

        (bool success,) = tokenMessenger.delegatecall(data);
        if (!success) {
            revert ExecutionFailed();
        }
    }
}
