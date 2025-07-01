// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

/**
 * @title AnypayRelayConstants
 * @author Shun Kakinoki
 * @notice Shared constants for all Anypay Relay libraries.
 */
library AnypayRelayConstants {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    address public constant RELAY_SOLVER = 0xf70da97812CB96acDF810712Aa562db8dfA3dbEF;
    address public constant RELAY_APPROVAL_PROXY = 0xaaaaaaae92Cc1cEeF79a038017889fDd26D23D4d;
    address public constant RELAY_APPROVAL_PROXY_V2 = 0xBBbfD134E9b44BfB5123898BA36b01dE7ab93d98;
    address public constant RELAY_RECEIVER = 0xa5F565650890fBA1824Ee0F21EbBbF660a179934;
}
