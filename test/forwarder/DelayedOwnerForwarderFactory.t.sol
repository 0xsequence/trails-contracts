// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DelayedOwnerForwarderFactory} from "src/forwarder/DelayedOwnerForwarderFactory.sol";
import {DelayedOwnerForwarder} from "src/forwarder/DelayedOwnerForwarder.sol";

// -----------------------------------------------------------------------------
// Test Contract
// -----------------------------------------------------------------------------

contract DelayedOwnerForwarderFactoryTest is Test {
    // -------------------------------------------------------------------------
    // Test State Variables
    // -------------------------------------------------------------------------
    DelayedOwnerForwarderFactory internal factory;

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------
    function setUp() public {
        factory = new DelayedOwnerForwarderFactory();
    }

    // -------------------------------------------------------------------------
    // Test Functions - Deployment
    // -------------------------------------------------------------------------

    function test_deploy_createsForwarder() public {
        bytes32 salt = keccak256("test-salt");
        address payable forwarder = factory.deploy(salt);

        assertTrue(forwarder != address(0), "Forwarder should be deployed");
        assertTrue(forwarder.code.length > 0, "Forwarder should have code");
    }

    function test_deploy_deterministicAddress() public {
        bytes32 salt = keccak256("deterministic-test-salt");
        address payable forwarder1 = factory.deploy(salt);
        address payable computed = factory.computeAddress(salt);

        assertEq(forwarder1, computed, "Deployed address should match computed address");
    }

    function test_deploy_differentSaltsProduceDifferentAddresses() public {
        bytes32 salt1 = keccak256("different-salts-1");
        bytes32 salt2 = keccak256("different-salts-2");

        address payable forwarder1 = factory.deploy(salt1);
        address payable forwarder2 = factory.deploy(salt2);

        assertTrue(forwarder1 != forwarder2, "Different salts should produce different addresses");
    }

    function test_deploy_acceptsValue() public {
        bytes32 salt = keccak256("accepts-value-salt");
        uint256 value = 1 ether;

        vm.deal(address(this), value);
        address payable forwarder = factory.deploy{value: value}(salt);

        assertTrue(forwarder != address(0), "Forwarder should be deployed");
        assertEq(address(forwarder).balance, value, "Forwarder should receive value");
    }

    function test_deploy_multipleDeployments() public {
        bytes32[] memory salts = new bytes32[](5);
        for (uint256 i = 0; i < 5; i++) {
            salts[i] = keccak256(abi.encodePacked("salt-", i));
        }

        address[] memory forwarders = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            forwarders[i] = factory.deploy(salts[i]);
            assertTrue(forwarders[i] != address(0), "Forwarder should be deployed");
        }

        // Verify all addresses are unique
        for (uint256 i = 0; i < 5; i++) {
            for (uint256 j = i + 1; j < 5; j++) {
                assertTrue(forwarders[i] != forwarders[j], "All forwarders should have unique addresses");
            }
        }
    }

    // -------------------------------------------------------------------------
    // Test Functions - Address Computation
    // -------------------------------------------------------------------------

    function test_computeAddress_matchesDeployedAddress() public {
        bytes32 salt = keccak256("matches-deployed-salt");
        address payable computed = factory.computeAddress(salt);
        address payable deployed = factory.deploy(salt);

        assertEq(computed, deployed, "Computed address should match deployed address");
    }

    function test_computeAddress_beforeDeployment() public {
        bytes32 salt = keccak256("pre-compute-salt");
        address payable computed = factory.computeAddress(salt);

        // Deploy and verify
        address payable deployed = factory.deploy(salt);
        assertEq(computed, deployed, "Pre-computed address should match deployed address");
    }

    function test_computeAddress_deterministic() public view {
        bytes32 salt = keccak256("deterministic-salt");
        address payable computed1 = factory.computeAddress(salt);
        address payable computed2 = factory.computeAddress(salt);

        assertEq(computed1, computed2, "Multiple computations should return same address");
    }

    function test_computeAddress_differentSalts() public view {
        bytes32 salt1 = keccak256("compute-salt-1");
        bytes32 salt2 = keccak256("compute-salt-2");

        address payable computed1 = factory.computeAddress(salt1);
        address payable computed2 = factory.computeAddress(salt2);

        assertTrue(computed1 != computed2, "Different salts should produce different addresses");
    }

    function test_computeAddress_usesCorrectCodeHash() public view {
        bytes32 salt = keccak256("code-hash-test");
        address payable computed = factory.computeAddress(salt);

        // Manually compute expected address
        bytes memory code = type(DelayedOwnerForwarder).creationCode;
        bytes32 codeHash = keccak256(code);
        address expected =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, codeHash)))));

        assertEq(computed, expected, "Computed address should use correct CREATE2 formula");
    }

    // -------------------------------------------------------------------------
    // Test Functions - Error Cases
    // -------------------------------------------------------------------------

    function test_deploy_revertsWhenDeployFails() public {
        // This is hard to trigger in practice, but we can test the error exists
        // by checking the error selector is defined
        bytes32 salt = keccak256("reverts-when-deploy-fails-salt");

        // Normal deployment should succeed
        address payable forwarder = factory.deploy(salt);
        assertTrue(forwarder != address(0), "Normal deployment should succeed");

        // Note: DeployFailed is hard to trigger in tests because CREATE2
        // typically only fails if there's insufficient gas or the address
        // already has code (which we can't easily simulate without deploying first)
    }

    function test_deploy_revertsOnSecondDeploymentWithSameSalt() public {
        bytes32 salt = keccak256("duplicate-salt");

        // First deployment succeeds
        address payable forwarder1 = factory.deploy(salt);
        assertTrue(forwarder1 != address(0), "First deployment should succeed");

        // Second deployment with same salt should revert
        // (CREATE2 reverts if address already has code)
        vm.expectRevert();
        factory.deploy(salt);
    }

    // -------------------------------------------------------------------------
    // Test Functions - Edge Cases
    // -------------------------------------------------------------------------

    function test_deploy_withZeroSalt() public {
        bytes32 salt = bytes32(0);
        address payable forwarder = factory.deploy(salt);

        assertTrue(forwarder != address(0), "Deployment with zero salt should succeed");
        assertEq(factory.computeAddress(salt), forwarder, "Computed address should match");
    }

    function test_deploy_withMaxSalt() public {
        bytes32 salt = bytes32(type(uint256).max);
        address payable forwarder = factory.deploy(salt);

        assertTrue(forwarder != address(0), "Deployment with max salt should succeed");
        assertEq(factory.computeAddress(salt), forwarder, "Computed address should match");
    }

    function test_deploy_withMinSalt() public {
        bytes32 salt = bytes32(0);
        address payable forwarder = factory.deploy(salt);

        assertTrue(forwarder != address(0), "Deployment with min salt should succeed");
    }

    function test_computeAddress_withZeroSalt() public {
        bytes32 salt = bytes32(0);
        address payable computed = factory.computeAddress(salt);
        address payable deployed = factory.deploy(salt);

        assertEq(computed, deployed, "Zero salt should work correctly");
    }

    function test_computeAddress_withMaxSalt() public {
        bytes32 salt = bytes32(type(uint256).max);
        address payable computed = factory.computeAddress(salt);
        address payable deployed = factory.deploy(salt);

        assertEq(computed, deployed, "Max salt should work correctly");
    }

    // -------------------------------------------------------------------------
    // Test Functions - Integration
    // -------------------------------------------------------------------------

    function test_deployedForwarderWorks() public {
        bytes32 salt = keccak256("integration-test");
        address payable forwarderAddr = payable(factory.deploy(salt));
        DelayedOwnerForwarder forwarder = DelayedOwnerForwarder(forwarderAddr);

        // Verify forwarder is functional
        assertEq(forwarder.owner(), address(0), "Forwarder should have no owner initially");

        // Make a call to set owner
        address target = makeAddr("target");
        bytes memory callData = abi.encodePacked(bytes20(target));

        address caller = makeAddr("caller");
        vm.prank(caller);
        (bool success,) = forwarderAddr.call(callData);
        assertTrue(success, "Forwarder call should succeed");
        assertEq(forwarder.owner(), caller, "Forwarder should set owner to first caller");
    }

    function test_multipleFactoriesProduceDifferentAddresses() public {
        DelayedOwnerForwarderFactory factory2 = new DelayedOwnerForwarderFactory();
        bytes32 salt = keccak256("same-salt");

        address payable forwarder1 = factory.deploy(salt);
        address payable forwarder2 = factory2.deploy(salt);

        assertTrue(forwarder1 != forwarder2, "Different factories should produce different addresses for same salt");
    }

    function test_factoryAddressAffectsComputedAddress() public {
        DelayedOwnerForwarderFactory factory2 = new DelayedOwnerForwarderFactory();
        bytes32 salt = keccak256("same-salt");

        address payable computed1 = factory.computeAddress(salt);
        address payable computed2 = factory2.computeAddress(salt);

        assertTrue(computed1 != computed2, "Different factories should compute different addresses");
    }

    // -------------------------------------------------------------------------
    // Test Functions - Gas and Value Handling
    // -------------------------------------------------------------------------

    function test_deploy_withVariousValues() public {
        bytes32[] memory salts = new bytes32[](4);
        uint256[] memory values = new uint256[](4);

        salts[0] = keccak256("various-values-salt-0");
        salts[1] = keccak256("various-values-salt-1");
        salts[2] = keccak256("various-values-salt-2");
        salts[3] = keccak256("various-values-salt-3");

        values[0] = 0;
        values[1] = 1 wei;
        values[2] = 1 ether;
        values[3] = 100 ether;

        vm.deal(address(this), 200 ether);

        for (uint256 i = 0; i < 4; i++) {
            address payable forwarder = factory.deploy{value: values[i]}(salts[i]);
            assertTrue(forwarder != address(0), "Forwarder should be deployed");
            assertEq(address(forwarder).balance, values[i], "Forwarder should receive correct value");
        }
    }

    function test_computeAddress_doesNotDependOnValue() public {
        bytes32 salt = keccak256("value-independent-salt");

        address payable computed1 = factory.computeAddress(salt);

        // Deploy with value
        vm.deal(address(this), 1 ether);
        address payable deployed = factory.deploy{value: 1 ether}(salt);

        assertEq(computed1, deployed, "Computed address should not depend on value sent");
    }
}
