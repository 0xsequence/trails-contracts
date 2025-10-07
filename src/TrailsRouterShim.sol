// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Storage} from "../lib/wallet-contracts-v3/src/modules/Storage.sol";
import {TrailsSentinelLib} from "./libraries/TrailsSentinelLib.sol";

/// @title TrailsRouterShim
/// @notice Sequence delegate-call extension that forwards Trails router calls and records success sentinels.
contract TrailsRouterShim {
    // -------------------------------------------------------------------------
    // Immutable variables
    // -------------------------------------------------------------------------

    /// @notice Address of the deployed TrailsMulticall3Router to forward calls to
    address public immutable ROUTER;
    /// @dev Cached address of this contract to detect delegatecall context
    address private immutable SELF = address(this);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NotDelegateCall();
    error RouterCallFailed(bytes data);
    error ZeroRouterAddress();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address router_) {
        if (router_ == address(0)) revert ZeroRouterAddress();
        ROUTER = router_;
    }

    // -------------------------------------------------------------------------
    // Sequence delegated entry point
    // -------------------------------------------------------------------------

    function handleSequenceDelegateCall(
        bytes32 opHash,
        uint256, // startingGas (unused)
        uint256, // index (unused)
        uint256, // numCalls (unused)
        uint256, // space (unused)
        bytes calldata data
    ) external payable onlyDelegatecall {
        // Decode the inner call data and call value forwarded to the router
        (bytes memory inner, uint256 callValue) = abi.decode(data, (bytes, uint256));
        bytes memory routerReturn = _forwardToRouter(inner, callValue);

        // Set the success sentinel storage slot for the opHash
        bytes32 slot = TrailsSentinelLib.successSlot(opHash);
        Storage.writeBytes32(slot, TrailsSentinelLib.SUCCESS_VALUE);

        assembly {
            return(add(routerReturn, 32), mload(routerReturn))
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _forwardToRouter(bytes memory forwardData, uint256 callValue) internal returns (bytes memory) {
        (bool success, bytes memory ret) = ROUTER.call{value: callValue}(forwardData);
        if (!success) {
            revert RouterCallFailed(ret);
        }
        return ret;
    }

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyDelegatecall() {
        if (address(this) == SELF) revert NotDelegateCall();
        _;
    }
}
