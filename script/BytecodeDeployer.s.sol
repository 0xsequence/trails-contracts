// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";

contract BytecodeDeployer is Script {
    // Predefined salt for deterministic deployment
    bytes32 public constant DEPLOY_SALT = keccak256(abi.encodePacked(bytes1(0x0), "trails-contracts"));

    // Expected deployment address (update with actual computed address)
    address public constant TARGET_ADDRESS = address(0);

    function run() external {
        // Get deployment configuration
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deployer Address:", deployer);
        console.log("Chain ID:", block.chainid);

        // Get bytecode from environment or compute
        bytes memory bytecode = getBytecode();
        bytes32 bytecodeHash = keccak256(bytecode);

        console.log("Bytecode Hash:");
        console.logBytes32(bytecodeHash);
        console.log("Bytecode Length:", bytecode.length);

        // Verify bytecode integrity if expected hash is provided
        bytes32 expectedHash = getExpectedBytecodeHash();
        if (expectedHash != bytes32(0)) {
            require(bytecodeHash == expectedHash, "Bytecode hash mismatch");
            console.log("Bytecode verification: PASSED");
        }

        vm.startBroadcast(deployerKey);

        address deployedAddress;

        // Deploy based on chain configuration
        if (isLocalChain()) {
            // Local development deployment
            deployedAddress = deployDirectly(bytecode);
        } else {
            // Production deployment with Create2
            deployedAddress = deployWithCreate2(bytecode, DEPLOY_SALT);
        }

        vm.stopBroadcast();

        // Post-deployment verification
        require(deployedAddress != address(0), "Deployment failed");
        console.log("Contract deployed at:", deployedAddress);

        address expectedAddress = _computeCreate2Address(DEPLOY_SALT, bytecodeHash);
        console.log("Expected address:", expectedAddress);

        // Verify deterministic address if configured
        if (TARGET_ADDRESS != address(0)) {
            require(deployedAddress == TARGET_ADDRESS, "Address mismatch");
            console.log("Address verification: PASSED");
        } else {
            require(deployedAddress == expectedAddress, "Address mismatch");
            console.log("Address verification: PASSED");
        }

        // Log deployment success
        console.log("Deployment completed successfully");
    }

    function getBytecode() internal pure virtual returns (bytes memory) {
        // Override this function to provide contract bytecode
        // Example: return type(YourContract).creationCode;
        revert("Override getBytecode() to provide contract bytecode");
    }

    function getExpectedBytecodeHash() internal pure virtual returns (bytes32) {
        // Override to provide expected bytecode hash for verification
        return bytes32(0);
    }

    function isLocalChain() internal view returns (bool) {
        // Foundry's anvil default chain ID
        return block.chainid == 31337;
    }

    function deployDirectly(bytes memory bytecode) internal returns (address) {
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "Direct deployment failed");
        return deployed;
    }

    function deployWithCreate2(bytes memory bytecode, bytes32 salt) internal returns (address) {
        address deployed;
        assembly {
            deployed := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(deployed != address(0), "Create2 deployment failed");
        return deployed;
    }

    function _computeCreate2Address(bytes32 salt, bytes32 initcodeHash) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initcodeHash)))));
    }
}
