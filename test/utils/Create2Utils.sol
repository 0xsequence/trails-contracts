// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SINGLETON_FACTORY_ADDR} from "lib/erc2470-libs/src/ISingletonFactory.sol";

// -----------------------------------------------------------------------------
// Library
// -----------------------------------------------------------------------------

/// @title Create2 Address Calculation Utilities
/// @notice Utility functions for calculating CREATE2 addresses used in deployment tests
library Create2Utils {
    /// @dev Calculate the expected CREATE2 address for a contract deployment
    /// @param initCode The contract initialization code (creation code + constructor args if any)
    /// @param salt The salt used for CREATE2 deployment
    /// @return expectedAddr The expected address where the contract will be deployed
    function calculateCreate2Address(bytes memory initCode, bytes32 salt)
        internal
        pure
        returns (address payable expectedAddr)
    {
        expectedAddr = payable(address(
                uint160(
                    uint256(
                        keccak256(abi.encodePacked(bytes1(0xff), SINGLETON_FACTORY_ADDR, salt, keccak256(initCode)))
                    )
                )
            ));
    }

    /// @dev Get the standard salt used for deterministic deployments (bytes32(0))
    /// @return salt The standard salt value
    function standardSalt() internal pure returns (bytes32 salt) {
        return bytes32(0);
    }
}
