// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Tstorish} from "tstorish/Tstorish.sol";
import {TrailsSentinelLib} from "./libraries/TrailsSentinelLib.sol";
import {ITrailsRouterShim} from "./interfaces/ITrailsRouterShim.sol";
import {DelegatecallGuard} from "./guards/DelegatecallGuard.sol";

/// @title TrailsRouterShim
/// @author Shun Kakinoki
/// @notice Sequence delegate-call extension that forwards Trails router calls and records success sentinels.
contract TrailsRouterShim is ITrailsRouterShim, DelegatecallGuard, Tstorish {
    // -------------------------------------------------------------------------
    // Immutable variables
    // -------------------------------------------------------------------------

    /// @notice Address of the deployed TrailsMulticall3Router to forward calls to
    address public immutable ROUTER;
    // SELF provided by DelegatecallGuard

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error RouterCallFailed(bytes data);
    error ZeroRouterAddress();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param router_ The address of the router to forward calls to
    constructor(address router_) {
        if (router_ == address(0)) revert ZeroRouterAddress();
        ROUTER = router_;
    }

    // -------------------------------------------------------------------------
    // Sequence delegated entry point
    // -------------------------------------------------------------------------

    /// @inheritdoc ITrailsRouterShim
    function handleSequenceDelegateCall(
        bytes32 opHash,
        uint256, // startingGas (unused)
        uint256, // index (unused)
        uint256, // numCalls (unused)
        uint256, // space (unused)
        bytes calldata data
    )
        external
        onlyDelegatecall
    {
        // Decode the inner call data and call value forwarded to the router
        (bytes memory inner, uint256 callValue) = abi.decode(data, (bytes, uint256));

        // Forward the call to the router
        bytes memory routerReturn = _forwardToRouter(inner, callValue);

        // Set the success sentinel storage slot for the opHash
        uint256 slot = TrailsSentinelLib.successSlot(opHash);
        _setTstorish(slot, TrailsSentinelLib.SUCCESS_VALUE);

        assembly {
            return(add(routerReturn, 32), mload(routerReturn))
        }
    }

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    /// forge-lint: disable-next-line(mixed-case-function)
    function _forwardToRouter(bytes memory forwardData, uint256 callValue) internal returns (bytes memory) {
        (bool success, bytes memory ret) = ROUTER.call{value: callValue}(forwardData);
        if (!success) {
            revert RouterCallFailed(ret);
        }
        return ret;
    }
}
