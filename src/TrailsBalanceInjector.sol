// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IDelegatedExtension {
    function handleSequenceDelegateCall(
        bytes32 _opHash,
        uint256 _startingGas,
        uint256 _callIndex,
        uint256 _numCalls,
        uint256 _space,
        bytes calldata _data
    ) external;
}

contract TrailsBalanceInjector is IDelegatedExtension {
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
     * @notice Handler for Sequence wallet delegatecalls
     * @dev Extracts the actual calldata and forwards to injectAndCall
     * Reference: https://github.com/0xsequence/wallet-contracts-v3/blob/6fe1cef932fadd69096623c1556d468f309f71e8/src/modules/interfaces/IDelegatedExtension.sol#L16
     */
    function handleSequenceDelegateCall(
        bytes32, /* _opHash */
        uint256, /* _startingGas */
        uint256, /* _callIndex */
        uint256, /* _numCalls */
        uint256, /* _space */
        bytes calldata _data
    ) external override {
        // Decode the inner injectAndCall call
        require(_data.length >= 4, "Invalid calldata");
        bytes4 selector = bytes4(_data[:4]);
        require(selector == this.injectAndCall.selector, "Invalid selector");

        // Decode parameters: (address token, address target, bytes calldata callData, uint256 amountOffset, bytes32 placeholder)
        (address token, address target, bytes memory callData, uint256 amountOffset, bytes32 placeholder) =
            abi.decode(_data[4:], (address, address, bytes, uint256, bytes32));

        // Call injectAndCall internally
        _injectAndCall(token, target, callData, amountOffset, placeholder);
    }

    /**
     * @notice Sweeps tokens from msg.sender and calls target
     * @dev For regular calls (not delegatecall). Transfers tokens from msg.sender to this contract first.
     * @param token The ERC-20 token to sweep, or address(0) for ETH.
     * @param target The address to call with modified calldata.
     * @param callData The original calldata (must include a 32-byte placeholder).
     * @param amountOffset The byte offset in calldata where the placeholder is located.
     * @param placeholder The 32-byte placeholder that will be replaced with balance (used for validation).
     */
    function injectSweepAndCall(
        address token,
        address target,
        bytes calldata callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) external payable {
        uint256 callerBalance;

        if (token == address(0)) {
            // Handle ETH - use msg.value
            callerBalance = msg.value;
            require(callerBalance > 0, "No ETH sent");
        } else {
            // Handle ERC20 - transfer from msg.sender
            callerBalance = IERC20(token).balanceOf(msg.sender);
            require(callerBalance > 0, "No tokens to sweep");

            // Transfer all tokens from caller to this contract
            bool transferred = IERC20(token).transferFrom(msg.sender, address(this), callerBalance);
            require(transferred, "TransferFrom failed");
        }

        // Execute the call with the balance
        _executeCall(token, target, callData, amountOffset, placeholder, callerBalance);
    }

    /**
     * @notice Injects balance and calls target (for delegatecall context)
     * @dev For delegatecalls from Sequence wallets. Reads balance from address(this).
     * @param token The ERC-20 token to sweep, or address(0) for ETH.
     * @param target The address to call with modified calldata.
     * @param callData The original calldata (must include a 32-byte placeholder).
     * @param amountOffset The byte offset in calldata where the placeholder is located.
     * @param placeholder The 32-byte placeholder that will be replaced with balance (used for validation).
     */
    function injectAndCall(
        address token,
        address target,
        bytes calldata callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) external payable {
        _injectAndCall(token, target, callData, amountOffset, placeholder);
    }

    /**
     * @dev Internal implementation of injectAndCall
     */
    function _injectAndCall(
        address token,
        address target,
        bytes memory callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) internal {
        uint256 callerBalance;

        if (token == address(0)) {
            // Always use address(this).balance, regardless of call type.
            // The contract must have ETH available before calling this function.
            callerBalance = address(this).balance;
            require(callerBalance > 0, "No ETH available in contract");
        } else {
            // Handle ERC20
            // When delegatecalled, address(this) is the wallet's address, so we read its token balance
            callerBalance = IERC20(token).balanceOf(address(this));
            require(callerBalance > 0, "No tokens to sweep");
        }

        // Execute the call with the balance
        _executeCall(token, target, callData, amountOffset, placeholder, callerBalance);
    }

    /**
     * @dev Internal function that handles calldata manipulation and execution
     * @param token The token address (or address(0) for ETH)
     * @param target The target contract to call
     * @param callData The calldata to modify and forward
     * @param amountOffset The offset where to inject the balance
     * @param placeholder The placeholder to replace
     * @param callerBalance The balance to inject
     */
    function _executeCall(
        address token,
        address target,
        bytes memory callData,
        uint256 amountOffset,
        bytes32 placeholder,
        uint256 callerBalance
    ) internal {
        // Copy calldata into memory
        bytes memory data = callData;

        // If amountOffset and placeholder are both zero, skip replacement logic
        bool shouldReplace = (amountOffset != 0 || placeholder != bytes32(0));

        if (shouldReplace) {
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
