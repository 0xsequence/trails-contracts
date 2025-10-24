// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title MockNonStandardERC20
 * @notice Mock ERC20 token that doesn't return boolean from transfer/transferFrom
 * @dev Mimics tokens like USDT that don't follow the ERC20 standard strictly
 */
contract MockNonStandardERC20 {
    string public name = "Non-Standard Token";
    string public symbol = "NST";
    uint8 public decimals = 6;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(uint256 initialSupply) {
        totalSupply = initialSupply;
        balanceOf[msg.sender] = initialSupply;
        emit Transfer(address(0), msg.sender, initialSupply);
    }

    /**
     * @notice Transfer tokens - DOES NOT RETURN A BOOLEAN (non-standard)
     * @dev This mimics USDT's behavior where transfer doesn't return a value
     */
    function transfer(address to, uint256 value) public {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        // NOTE: No return value (non-standard)
    }

    /**
     * @notice Transfer tokens from one address to another - DOES NOT RETURN A BOOLEAN (non-standard)
     * @dev This mimics USDT's behavior where transferFrom doesn't return a value
     */
    function transferFrom(address from, address to, uint256 value) public {
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Insufficient allowance");

        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;

        emit Transfer(from, to, value);
        // NOTE: No return value (non-standard)
    }

    /**
     * @notice Approve spender to spend tokens - DOES return a boolean (standard)
     */
    function approve(address spender, uint256 value) public returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @notice Mint tokens for testing
     */
    function mint(address to, uint256 amount) public {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}
