// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title TrailsCCTPUtils
 * @author Shun Kakinoki
 * @notice Utility library for CCTP operations.
 */
library TrailsCCTPUtils {
    error InvalidCCTPDomain(uint32 domain);

    /**
     * @notice Converts a CCTP domain to a chain ID.
     * @param domain The CCTP domain.
     * @return The chain ID.
     */
    function cctpDomainToChainId(uint32 domain) internal pure returns (uint256) {
        if (domain == 0) return 1; // Ethereum Mainnet
        if (domain == 1) return 43114; // Avalanche
        if (domain == 2) return 10; // Optimism
        if (domain == 3) return 42161; // Arbitrum
        if (domain == 6) return 8453; // Base
        if (domain == 7) return 137; // Polygon
        revert InvalidCCTPDomain(domain);
    }
}
