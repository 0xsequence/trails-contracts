// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Storage} from "wallet-contracts-v3/modules/Storage.sol";
import {TrailsSentinelLib} from "./libraries/TrailsSentinelLib.sol";
import {ITrailsRouterShim} from "./interfaces/ITrailsRouterShim.sol";

/// @title TrailsRouterShim
/// @author Shun Kakinoki
/// @notice Sequence delegate-call extension that forwards Trails router calls and records success sentinels.
contract TrailsRouterShim is ITrailsRouterShim {
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

    /// @inheritdoc ITrailsRouterShim
    function handleSequenceDelegateCall(
        bytes32 opHash,
        uint256, // startingGas (unused)
        uint256, // index (unused)
        uint256, // numCalls (unused)
        uint256, // space (unused)
        bytes calldata data
    ) external onlyDelegatecall {
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
    // Internal Helpers
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
        _onlyDelegatecall();
        _;
    }

    function _onlyDelegatecall() internal view {
        if (address(this) == SELF) revert NotDelegateCall();
    }
}
