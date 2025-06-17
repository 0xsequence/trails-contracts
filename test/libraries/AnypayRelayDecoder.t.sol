// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {AnypayRelayDecoder} from "@/libraries/AnypayRelayDecoder.sol";

// Helper contract to test the AnypayRelayDecoder library
contract RelayDecoderTestHelper {
    function decode(bytes calldata data) public payable returns (AnypayRelayDecoder.DecodedRelayData memory) {
        return AnypayRelayDecoder.decodeRelayCalldata(data);
    }
}

contract AnypayRelayDecoderTest is Test {
    RelayDecoderTestHelper public helper;
    address public user = makeAddr("user");
    bytes32 public constant TEST_REQUEST_ID = keccak256("test_request_id");

    function setUp() public {
        helper = new RelayDecoderTestHelper();
    }

    // -------------------------------------------------------------------------
    // Native Asset Transfer Tests
    // -------------------------------------------------------------------------

    function test_decode_nativeAssetTransfer_success() public {
        uint256 sentValue = 1 ether;
        bytes memory calldataToDecode = abi.encode(TEST_REQUEST_ID);

        // The test contract is the msg.sender to the helper
        AnypayRelayDecoder.DecodedRelayData memory decodedData = helper.decode{value: sentValue}(calldataToDecode);

        assertEq(decodedData.requestId, TEST_REQUEST_ID, "requestId mismatch");
        assertEq(decodedData.token, address(0), "token should be address(0)");
        assertEq(decodedData.amount, sentValue, "amount should be msg.value");
        assertEq(decodedData.receiver, address(this), "receiver should be msg.sender");
    }

    // -------------------------------------------------------------------------
    // ERC20 Transfer Tests
    // -------------------------------------------------------------------------

    function test_decode_erc20Transfer_success() public {
        address receiver = makeAddr("receiver");
        uint256 amount = 100 ether;

        bytes memory calldataToDecode =
            abi.encodePacked(bytes4(0xa9059cbb), abi.encode(receiver, amount, TEST_REQUEST_ID));

        AnypayRelayDecoder.DecodedRelayData memory decodedData = helper.decode(calldataToDecode);

        assertEq(decodedData.requestId, TEST_REQUEST_ID, "requestId mismatch");
        assertEq(decodedData.token, address(helper), "token should be address(this)");
        assertEq(decodedData.amount, amount, "amount mismatch");
        assertEq(decodedData.receiver, receiver, "receiver mismatch");
    }

    // -------------------------------------------------------------------------
    // Revert Tests
    // -------------------------------------------------------------------------

    function test_revert_invalidCalldataLength() public {
        bytes memory shortCalldata = hex"01020304";
        bytes memory longCalldata = new bytes(101);

        bytes memory expectedError = abi.encodeWithSelector(AnypayRelayDecoder.InvalidCalldataLength.selector);

        vm.expectRevert(expectedError);
        helper.decode(shortCalldata);

        vm.expectRevert(expectedError);
        helper.decode(longCalldata);
    }

    function test_revert_invalidSelector_erc20Transfer() public {
        address receiver = makeAddr("receiver");
        uint256 amount = 100 ether;

        bytes memory calldataToDecode =
            abi.encodePacked(bytes4(0xdeadbeef), abi.encode(receiver, amount, TEST_REQUEST_ID));

        bytes memory expectedError = abi.encodeWithSelector(AnypayRelayDecoder.InvalidCalldataLength.selector);
        vm.expectRevert(expectedError);
        helper.decode(calldataToDecode);
    }

    function testFuzz_nativeAssetTransfer(uint128 amount, bytes32 requestId) public {
        vm.assume(amount > 0);
        vm.assume(requestId != bytes32(0));

        uint256 sentValue = uint256(amount);
        vm.deal(address(this), sentValue); // Set balance for the native value transfer
        bytes memory calldataToDecode = abi.encode(requestId);

        // The test contract is the msg.sender to the helper
        AnypayRelayDecoder.DecodedRelayData memory decodedData =
            helper.decode{value: sentValue}(calldataToDecode);

        assertEq(decodedData.requestId, requestId, "requestId mismatch");
        assertEq(decodedData.token, address(0), "token should be address(0)");
        assertEq(decodedData.amount, sentValue, "amount should be msg.value");
        assertEq(decodedData.receiver, address(this), "receiver should be msg.sender");
    }

    function testFuzz_erc20Transfer(address receiver, uint128 amount, bytes32 requestId) public {
        vm.assume(receiver != address(0));
        vm.assume(amount > 0);
        vm.assume(requestId != bytes32(0));

        uint256 transferAmount = uint256(amount);

        bytes memory calldataToDecode =
            abi.encodePacked(bytes4(0xa9059cbb), abi.encode(receiver, transferAmount, requestId));

        AnypayRelayDecoder.DecodedRelayData memory decodedData = helper.decode(calldataToDecode);

        assertEq(decodedData.requestId, requestId, "requestId mismatch");
        assertEq(decodedData.token, address(helper), "token should be address(this)");
        assertEq(decodedData.amount, transferAmount, "amount mismatch");
        assertEq(decodedData.receiver, receiver, "receiver mismatch");
    }
}
