// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IDelegatedExtension} from "wallet-contracts-v3/modules/interfaces/IDelegatedExtension.sol";
import {Storage} from "wallet-contracts-v3/modules/Storage.sol";

/// @title TrailsRouterShim
/// @notice Sequence delegate-call extension that forwards Trails router calls and records success sentinels.
contract TrailsRouterShim {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Namespace for marking successful router execution in wallet storage
    bytes32 public constant ROUTER_SENTINEL_NAMESPACE = keccak256("org.sequence.trails.router.sentinel");
    /// @notice Sentinel value written to storage upon router success
    bytes32 public constant ROUTER_SUCCESS_VALUE = bytes32(uint256(1));

    // -------------------------------------------------------------------------
    // Immutable variables
    // -------------------------------------------------------------------------

    /// @notice Address of the deployed TrailsMulticall3Router to forward calls to
    address public immutable router;
    /// @dev Cached address of this contract to detect delegatecall context
    address private immutable SELF = address(this);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InvalidSelector(bytes4 selector);
    error NotDelegateCall();
    error RouterCallFailed(bytes data);
    error ZeroRouterAddress();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address router_) {
        if (router_ == address(0)) revert ZeroRouterAddress();
        router = router_;
    }

    // -------------------------------------------------------------------------
    // Sequence delegated entry point
    // -------------------------------------------------------------------------

    function handleSequenceDelegateCall(
        bytes32 opHash,
        uint256, // startingGas (unused)
        uint256 index,
        uint256, // numCalls (unused)
        uint256, // space (unused)
        bytes calldata data
    ) external payable onlyDelegatecall {
        if (data.length < 4) revert InvalidSelector(0x00000000);

        bytes memory forwardData = data;

        bytes memory routerReturn = _forwardToRouter(forwardData);

        Storage.writeBytes32(_successSlot(opHash, index), ROUTER_SUCCESS_VALUE);

        assembly {
            return(add(routerReturn, 32), mload(routerReturn))
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _forwardToRouter(bytes memory forwardData) internal returns (bytes memory) {
        (bool success, bytes memory ret) = router.call{value: msg.value}(forwardData);
        if (!success) {
            revert RouterCallFailed(ret);
        }
        return ret;
    }

    function _successSlot(bytes32 opHash, uint256 index) internal pure returns (bytes32) {
        return keccak256(abi.encode(ROUTER_SENTINEL_NAMESPACE, opHash, index));
    }

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyDelegatecall() {
        if (address(this) == SELF) revert NotDelegateCall();
        _;
    }
}
