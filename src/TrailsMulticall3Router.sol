// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";

/**
 * @title TrailsMulticall3Router
 * @author Shun Kakinoki
 * @notice A wrapper to execute multiple calls via DELEGATECALL to preserve the original msg.sender.
 * @dev This contract mimics the Multicall3 interface but executes sub-calls via DELEGATECALL
 *      to ensure that for the sub-calls, msg.sender is the original caller of this contract.
 *      This is useful for smart contract wallets (intent addresses) that need to control msg.sender.
 */
contract TrailsMulticall3Router {
    // -------------------------------------------------------------------------
    // Immutable Variables
    // -------------------------------------------------------------------------

    address public immutable multicall3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Aggregates multiple calls in a single transaction.
     * @dev See the contract-level documentation for the logic on how the call is performed.
     * @param data The data to execute.
     * @return returnResults The result of the execution. (Expects the underlying data returned to be an array of IMulticall3.Result)
     */
    function execute(bytes calldata data)
        public
        payable
        returns (IMulticall3.Result[] memory returnResults)
    {
        (bool success, bytes memory returnData) = multicall3.delegatecall(data);
        require(success, "TrailsMulticall3Router: call failed");
        return abi.decode(returnData, (IMulticall3.Result[]));
    }

    // -------------------------------------------------------------------------
    // Receive ETH
    // -------------------------------------------------------------------------

    /// @notice Receive ETH
    receive() external payable {}
}
