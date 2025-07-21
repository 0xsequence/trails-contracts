// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/**
 * @title TrailsMulticall3Router
 * @author Shun Kakinoki
 * @notice A wrapper to execute multiple calls via DELEGATECALL to preserve the original msg.sender.
 * @dev This contract mimics the Multicall3 interface but executes sub-calls via DELEGATECALL
 *      to ensure that for the sub-calls, msg.sender is the original caller of this contract.
 *      This is useful for smart contract wallets (intent addresses) that need to control msg.sender.
 *      Additionally tracks deposits for emergency withdrawals when multicalls fail.
 */
contract TrailsMulticall3Router {
    // -------------------------------------------------------------------------
    // Constants & Immutable Variables
    // -------------------------------------------------------------------------

    address public immutable multicall3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // -------------------------------------------------------------------------
    // Storage Variables
    // -------------------------------------------------------------------------

    mapping(address => mapping(address => uint256)) public deposits;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);

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
        if (msg.value > 0) {
            deposits[msg.sender][ETH_ADDRESS] += msg.value;
            emit Deposit(msg.sender, ETH_ADDRESS, msg.value);
        }

        (bool success, bytes memory returnData) = multicall3.delegatecall(data);
        require(success, "TrailsMulticall3Router: call failed");
        return abi.decode(returnData, (IMulticall3.Result[]));
    }

    function aggregate3(IMulticall3.Call3[] calldata calls)
        public
        payable
        returns (IMulticall3.Result[] memory returnResults)
    {
        if (msg.value > 0) {
            deposits[msg.sender][ETH_ADDRESS] += msg.value;
            emit Deposit(msg.sender, ETH_ADDRESS, msg.value);
        }

        bytes memory data = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);
        (bool success, bytes memory returnData) = multicall3.delegatecall(data);
        require(success, "TrailsMulticall3Router: call failed");
        return abi.decode(returnData, (IMulticall3.Result[]));
    }

    /**
     * @notice Deposit ERC20 tokens to be tracked for emergency withdrawal.
     * @param token The ERC20 token address to deposit.
     * @param amount The amount of tokens to deposit.
     */
    function depositToken(address token, uint256 amount) external {
        require(token != ETH_ADDRESS, "Use ETH deposit via execute()");
        require(amount > 0, "Amount must be greater than 0");

        IERC20(token).transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender][token] += amount;
        emit Deposit(msg.sender, token, amount);
    }

    /**
     * @notice Emergency withdrawal of deposited ETH.
     * @param amount The amount of ETH to withdraw.
     */
    function withdrawETH(uint256 amount) external {
        require(deposits[msg.sender][ETH_ADDRESS] >= amount, "Insufficient ETH balance");
        
        deposits[msg.sender][ETH_ADDRESS] -= amount;
        emit Withdraw(msg.sender, ETH_ADDRESS, amount);
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    /**
     * @notice Emergency withdrawal of deposited ERC20 tokens.
     * @param token The ERC20 token address to withdraw.
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawToken(address token, uint256 amount) external {
        require(token != ETH_ADDRESS, "Use withdrawETH() for ETH");
        require(deposits[msg.sender][token] >= amount, "Insufficient token balance");
        
        deposits[msg.sender][token] -= amount;
        emit Withdraw(msg.sender, token, amount);
        
        IERC20(token).transfer(msg.sender, amount);
    }

    /**
     * @notice Get the deposited balance for a user and token.
     * @param user The user address.
     * @param token The token address (use ETH_ADDRESS for ETH).
     * @return The deposited balance.
     */
    function getDeposit(address user, address token) external view returns (uint256) {
        return deposits[user][token];
    }

    // -------------------------------------------------------------------------
    // Receive ETH
    // -------------------------------------------------------------------------

    /// @notice Receive ETH and track as deposit
    receive() external payable {
        if (msg.value > 0) {
            deposits[msg.sender][ETH_ADDRESS] += msg.value;
            emit Deposit(msg.sender, ETH_ADDRESS, msg.value);
        }
    }
}
