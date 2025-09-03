// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Local interface definitions to avoid import issues
interface IMulticall3 {
    struct Call3 {
        address target;
        bool allowFailure;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    function aggregate3(Call3[] calldata calls) external payable returns (Result[] memory returnData);
}

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

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
    // Public Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Aggregates multiple calls in a single transaction.
     * @dev See the contract-level documentation for the logic on how the call is performed.
     * @param data The data to execute.
     * @return returnResults The result of the execution. (Expects the underlying data returned to be an array of IMulticall3.Result)
     */
    function execute(bytes calldata data) public payable returns (IMulticall3.Result[] memory returnResults) {
        (bool success, bytes memory returnData) = multicall3.delegatecall(data);
        require(success, "TrailsMulticall3Router: call failed");
        return abi.decode(returnData, (IMulticall3.Result[]));
    }

    /**
     * @notice Pull ERC20 from msg.sender, then delegatecall into Multicall3.
     * @dev Requires prior approval to this router for at least 'amount'.
     *      Reverts if transferFrom or the delegatecall fails. Returns IMulticall3.Result[].
     */
    function pullAndExecute(address token, uint256 amount, bytes calldata data)
        public
        payable
        returns (IMulticall3.Result[] memory returnResults)
    {
        if (token != address(0)) {
            _safeTransferFrom(token, msg.sender, address(this), amount);
        }

        (bool success, bytes memory returnData) = multicall3.delegatecall(data);
        require(success, "TrailsMulticall3Router: pullAndExecute failed");
        return abi.decode(returnData, (IMulticall3.Result[]));
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory res) = token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        require(ok && (res.length == 0 || abi.decode(res, (bool))), "TrailsMulticall3Router: transferFrom failed");
    }

    // -------------------------------------------------------------------------
    // Receive ETH
    // -------------------------------------------------------------------------

    /// @notice Receive ETH
    receive() external payable {}
}
