// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {TrailsLiFiRouter} from "@/TrailsLiFiRouter.sol";
import {TrailsLiFiValidator} from "@/libraries/TrailsLiFiValidator.sol";
import {TrailsDecodingStrategy} from "@/interfaces/TrailsLiFi.sol";
import {MockLifiDiamond} from "test/mocks/MockLifiDiamond.sol";

contract TrailsLiFiRouterTest is Test {
    TrailsLiFiRouter public router;
    MockLifiDiamond public mockLifi;

    function setUp() public {
        mockLifi = new MockLifiDiamond();
        router = new TrailsLiFiRouter(address(mockLifi));
    }

    function test_constructor_reverts_with_zero_address() public {
        vm.expectRevert("Invalid LiFi Diamond address");
        new TrailsLiFiRouter(address(0));
    }

    function test_execute_valid() public {
        ILiFi.BridgeData memory bridgeData = ILiFi.BridgeData({
            transactionId: bytes32(uint256(1)),
            bridge: "across",
            integrator: "acme",
            referrer: address(0),
            sendingAssetId: address(0),
            receiver: address(this),
            minAmount: 1,
            destinationChainId: 1,
            hasSourceSwaps: false,
            hasDestinationCall: false
        });

        bytes memory liFiData = abi.encode(bridgeData);
        bytes memory data = abi.encode(TrailsDecodingStrategy.SINGLE_BRIDGE_DATA, liFiData);

        vm.expectRevert();
        router.execute(data);
    }

    function test_execute_reverts_with_invalid_data() public {
        ILiFi.BridgeData memory bridgeData = ILiFi.BridgeData({
            transactionId: bytes32(0), // Invalid transactionId
            bridge: "across",
            integrator: "acme",
            referrer: address(0),
            sendingAssetId: address(0),
            receiver: address(this),
            minAmount: 1,
            destinationChainId: 1,
            hasSourceSwaps: false,
            hasDestinationCall: false
        });

        bytes memory liFiData = abi.encode(bridgeData);
        bytes memory data = abi.encode(TrailsDecodingStrategy.SINGLE_BRIDGE_DATA, liFiData);

        vm.expectRevert();
        router.execute(data);
    }
}
