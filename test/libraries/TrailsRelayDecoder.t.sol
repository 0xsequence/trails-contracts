// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {TrailsRelayDecoder} from "@/libraries/TrailsRelayDecoder.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

// Helper contract to test the TrailsRelayDecoder library
contract RelayDecoderTestHelper {
    function decodeForSapient_native(bytes calldata data, uint256 value, address to)
        public
        pure
        returns (TrailsRelayDecoder.DecodedRelayData memory)
    {
        Payload.Call memory call = Payload.Call({
            to: to,
            value: value,
            data: data,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: 0
        });
        return TrailsRelayDecoder.decodeRelayCalldataForSapient(call);
    }

    function decodeForSapient_erc20(bytes calldata data, address to)
        public
        pure
        returns (TrailsRelayDecoder.DecodedRelayData memory)
    {
        Payload.Call memory call = Payload.Call({
            to: to,
            value: 0,
            data: data,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: 0
        });
        return TrailsRelayDecoder.decodeRelayCalldataForSapient(call);
    }
}

contract TrailsRelayDecoderTest is Test {
    RelayDecoderTestHelper public helper;
    address public user = makeAddr("user");
    bytes32 public constant TEST_REQUEST_ID = keccak256("test_request_id");
    address private constant RELAY_RECEIVER = 0xa5F565650890fBA1824Ee0F21EbBbF660a179934;
    address private constant RELAY_SOLVER = 0xf70da97812CB96acDF810712Aa562db8dfA3dbEF;

    function setUp() public {
        helper = new RelayDecoderTestHelper();
    }

    // -------------------------------------------------------------------------
    // Native Asset Transfer Tests
    // -------------------------------------------------------------------------

    function test_decodeForSapient_native_success_as_receiver() public view {
        uint256 sentValue = 1 ether;
        bytes memory calldataToDecode = abi.encode(TEST_REQUEST_ID);

        // The test contract is the msg.sender to the helper
        TrailsRelayDecoder.DecodedRelayData memory decodedData =
            helper.decodeForSapient_native(calldataToDecode, sentValue, address(this));

        assertEq(decodedData.requestId, TEST_REQUEST_ID, "requestId mismatch");
        assertEq(decodedData.token, address(0), "token should be address(0)");
        assertEq(decodedData.amount, sentValue, "amount should be msg.value");
        assertEq(decodedData.receiver, address(this), "receiver should be msg.sender");
    }

    // -------------------------------------------------------------------------
    // ERC20 Transfer Tests
    // -------------------------------------------------------------------------

    function test_decodeForSapient_erc20_success_to_token() public {
        address receiver = makeAddr("receiver");
        uint256 amount = 100 ether;

        bytes memory calldataToDecode =
            abi.encodePacked(bytes4(0xa9059cbb), abi.encode(receiver, amount, TEST_REQUEST_ID));

        TrailsRelayDecoder.DecodedRelayData memory decodedData =
            helper.decodeForSapient_erc20(calldataToDecode, address(this));

        assertEq(decodedData.requestId, TEST_REQUEST_ID, "requestId mismatch");
        assertEq(decodedData.token, address(this), "token should be address(this)");
        assertEq(decodedData.amount, amount, "amount mismatch");
        assertEq(decodedData.receiver, receiver, "receiver mismatch");
    }

    // -------------------------------------------------------------------------
    // Revert Tests
    // -------------------------------------------------------------------------

    function test_revert_invalidCalldataLength() public {
        bytes memory shortCalldata = hex"01020304";
        bytes memory longCalldata = new bytes(101);

        bytes memory expectedError = abi.encodeWithSelector(TrailsRelayDecoder.InvalidCalldataLength.selector);

        vm.expectRevert(expectedError);
        helper.decodeForSapient_native(shortCalldata, 0, address(this));

        vm.expectRevert(expectedError);
        helper.decodeForSapient_native(longCalldata, 0, address(this));
    }

    function test_revert_invalidSelector_erc20Transfer() public {
        address receiver = makeAddr("receiver");
        uint256 amount = 100 ether;

        bytes memory calldataToDecode =
            abi.encodePacked(bytes4(0xdeadbeef), abi.encode(receiver, amount, TEST_REQUEST_ID));

        bytes memory expectedError = abi.encodeWithSelector(TrailsRelayDecoder.InvalidCalldataLength.selector);
        vm.expectRevert(expectedError);
        helper.decodeForSapient_erc20(calldataToDecode, address(this));
    }

    function testFuzz_nativeAssetTransfer(uint128 amount, bytes32 requestId) public {
        vm.assume(amount > 0);
        vm.assume(requestId != bytes32(0));

        uint256 sentValue = uint256(amount);
        vm.deal(address(this), sentValue); // Set balance for the native value transfer
        bytes memory calldataToDecode = abi.encode(requestId);

        // The test contract is the msg.sender to the helper
        TrailsRelayDecoder.DecodedRelayData memory decodedData =
            helper.decodeForSapient_native(calldataToDecode, sentValue, address(this));

        assertEq(decodedData.requestId, requestId, "requestId mismatch");
        assertEq(decodedData.token, address(0), "token should be address(0)");
        assertEq(decodedData.amount, sentValue, "amount should be msg.value");
        assertEq(decodedData.receiver, address(this), "receiver should be msg.sender");
    }

    function testFuzz_erc20Transfer(address receiver, uint128 amount, bytes32 requestId) public view {
        vm.assume(receiver != address(0));
        vm.assume(amount > 0);
        vm.assume(requestId != bytes32(0));

        uint256 transferAmount = uint256(amount);

        bytes memory calldataToDecode =
            abi.encodePacked(bytes4(0xa9059cbb), abi.encode(receiver, transferAmount, requestId));

        TrailsRelayDecoder.DecodedRelayData memory decodedData =
            helper.decodeForSapient_erc20(calldataToDecode, address(this));

        assertEq(decodedData.requestId, requestId, "requestId mismatch");
        assertEq(decodedData.token, address(this), "token should be address(this)");
        assertEq(decodedData.amount, transferAmount, "amount mismatch");
        assertEq(decodedData.receiver, receiver, "receiver mismatch");
    }

    // -------------------------------------------------------------------------
    // Sapient Decoder Tests
    // -------------------------------------------------------------------------

    function test_decodeForSapient_native_success_to_eoa() public {
        uint256 sentValue = 1 ether;
        bytes memory calldataToDecode = abi.encode(TEST_REQUEST_ID);
        address to = makeAddr("to");

        TrailsRelayDecoder.DecodedRelayData memory decodedData =
            helper.decodeForSapient_native(calldataToDecode, sentValue, to);

        assertEq(decodedData.requestId, TEST_REQUEST_ID, "requestId mismatch");
        assertEq(decodedData.token, address(0), "token should be address(0)");
        assertEq(decodedData.amount, sentValue, "amount should be value");
        assertEq(decodedData.receiver, to, "receiver should be to");
    }

    function test_decodeForSapient_erc20_success_to_eoa() public {
        address receiver = makeAddr("receiver");
        uint256 amount = 100 ether;
        address to = makeAddr("to");

        bytes memory calldataToDecode =
            abi.encodePacked(bytes4(0xa9059cbb), abi.encode(receiver, amount, TEST_REQUEST_ID));

        TrailsRelayDecoder.DecodedRelayData memory decodedData = helper.decodeForSapient_erc20(calldataToDecode, to);

        assertEq(decodedData.requestId, TEST_REQUEST_ID, "requestId mismatch");
        assertEq(decodedData.token, to, "token should be to address");
        assertEq(decodedData.amount, amount, "amount mismatch");
        assertEq(decodedData.receiver, receiver, "receiver mismatch");
    }

    function test_decodeForSapient_erc20_approve() public view {
        address tokenAddress = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address spender = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;
        uint256 amount = 0x7fffffffffffffff;
        bytes memory calldataToDecode = abi.encodeWithSelector(bytes4(0x095ea7b3), spender, amount);

        TrailsRelayDecoder.DecodedRelayData memory decodedData =
            helper.decodeForSapient_erc20(calldataToDecode, tokenAddress);

        assertEq(decodedData.requestId, bytes32(0), "requestId should be zero for approve");
        assertEq(decodedData.token, tokenAddress, "token should be the token address");
        assertEq(decodedData.amount, amount, "amount should be the approval amount");
        assertEq(decodedData.receiver, spender, "receiver should be the spender");
    }

    function testDecodeRelayCalldataForSapient_forward() public pure {
        bytes32 requestId = keccak256("test_request_id");
        uint256 value = 1 ether;

        Payload.Call memory call;
        call.to = RELAY_RECEIVER;
        call.value = value;
        call.data = abi.encodeWithSelector(0xd948d468, abi.encode(requestId));

        TrailsRelayDecoder.DecodedRelayData memory decodedData = TrailsRelayDecoder.decodeRelayCalldataForSapient(call);

        assertEq(decodedData.requestId, requestId);
        assertEq(decodedData.token, address(0));
        assertEq(decodedData.amount, value);
        assertEq(decodedData.receiver, RELAY_SOLVER);
    }

    function test_revert_when_decoding_relay_calldata() public {
        address to = 0xF5042e6ffaC5a625D4E7848e0b01373D8eB9e222;
        uint256 value = 735346664605744126;
        bytes memory data =
            hex"30be55670000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000005400000000000000000000000000000000000001ff3684f28c67538d4d072c2273400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a3479e53a97fbfe000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000004442213bc0b000000000000000000000000a3d370e8a4180828f6756cb8dce359cf21d9d6f700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a3479e53a97fbfe000000000000000000000000a3d370e8a4180828f6756cb8dce359cf21d9d6f700000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000003641fff991f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a09d4bddb88a2fc34f9b011a070af43c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000000000000000010438c9c147000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000027100000000000000000000000000d500b1d8e8ef31e21c99d1db9a6444d3adf1270000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000024d0e30db00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e48d68a156000000000000000000000000f5042e6ffac5a625d4e7848e0b01373d8eb9e22200000000000000000000000000000000000000000000000000000000000027100000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000001f66e000000000000000000000000000000000000000000000000000000000000002c0d500b1d8e8ef31e21c99d1db9a6444d3adf1270000000643c499c542cef5e3811e1192ce70d8cc03d5c33590000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f5042e6ffac5a625d4e7848e0b01373d8eb9e22200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000001243b2253c8000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000003c499c542cef5e3811e1192ce70d8cc03d5c33590000000000000000000000000000000000000000000000000000000000000001000000000000000000000000f70da97812cb96acdf810712aa562db8dfa3dbef0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f5f0f41b1550b7d3836bdf178dcec4067c52e7469040fdd4508a54a9fc70c11b";

        Payload.Call memory call;
        call.to = to;
        call.value = value;
        call.data = data;

        TrailsRelayDecoder.decodeRelayCalldataForSapient(call);
    }
}
