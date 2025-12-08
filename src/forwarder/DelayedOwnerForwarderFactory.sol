// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DelayedOwnerForwarder} from "./DelayedOwnerForwarder.sol";

/// @title DelayedOwnerForwarderFactory
/// @author Michael Standen
/// @notice A factory for deploying DelayedOwnerForwarder contracts using CREATE2.
contract DelayedOwnerForwarderFactory {
    error DeployFailed(bytes32 salt);

    function deploy(bytes32 salt) external payable returns (address payable forwarder) {
        bytes memory code = type(DelayedOwnerForwarder).creationCode;
        assembly {
            forwarder := create2(callvalue(), add(code, 32), mload(code), salt)
        }
        if (forwarder == address(0)) {
            revert DeployFailed(salt);
        }
    }

    function computeAddress(bytes32 salt) external view returns (address payable forwarder) {
        bytes memory code = type(DelayedOwnerForwarder).creationCode;
        bytes32 codeHash = keccak256(code);
        forwarder = payable(address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, codeHash))))
            ));
    }
}
