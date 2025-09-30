// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract TrailsBalanceInjector {
    event BalanceInjectorCall(
        address indexed token,
        address indexed target,
        bytes32 placeholder,
        uint256 amountReplaced,
        uint256 amountOffset,
        bool success,
        bytes result
    );

    /**
     * @notice Sweeps entire token balance of `token` and calls `target` with `callData`,
     *         replacing a 32-byte placeholder at `amountOffset` with the balance.
     * @param token The ERC-20 token to sweep, or address(0) for ETH.
     * @param target The address to call with modified calldata.
     * @param callData The original calldata (must include a 32-byte placeholder).
     * @param amountOffset The byte offset in calldata where the placeholder is located.
     * @param placeholder The 32-byte placeholder that will be replaced with balance (used for validation).
     */
    function sweepAndCall(
        address token,
        address target,
        bytes calldata callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) external payable {
        uint256 callerBalance;

        if (token == address(0)) {
            // Handle ETH
            callerBalance = msg.value;
            require(callerBalance > 0, "No ETH sent");
        } else {
            // Handle ERC20
            callerBalance = IERC20(token).balanceOf(msg.sender);
            require(callerBalance > 0, "No tokens to sweep");

            // Transfer all tokens from caller to this contract
            bool transferred = IERC20(token).transferFrom(msg.sender, address(this), callerBalance);
            require(transferred, "TransferFrom failed");
        }

        // Copy calldata into memory
        bytes memory data = callData;

        // Safety check: avoid overflow
        require(data.length >= amountOffset + 32, "amountOffset out of bounds");

        // Load the value at the offset to check for placeholder match
        bytes32 found;
        assembly {
            found := mload(add(add(data, 32), amountOffset))
        }
        require(found == placeholder, "Placeholder mismatch");

        // Replace the placeholder with the caller's balance
        assembly {
            mstore(add(add(data, 32), amountOffset), callerBalance)
        }

        if (token == address(0)) {
            // Make the call with ETH
            (bool success, bytes memory result) = target.call{value: callerBalance}(data);
            emit BalanceInjectorCall(token, target, placeholder, callerBalance, amountOffset, success, result);
            require(success, string(result));
        } else {
            // Approve target to spend tokens
            bool approved = IERC20(token).approve(target, callerBalance);
            require(approved, "Token approve failed");

            // Make the call without ETH
            (bool success, bytes memory result) = target.call(data);
            emit BalanceInjectorCall(token, target, placeholder, callerBalance, amountOffset, success, result);
            require(success, string(result));
        }
    }
}
