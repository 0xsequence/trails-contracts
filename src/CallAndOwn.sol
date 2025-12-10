// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract CallAndOwn {
    address public immutable factory;

    constructor(address _target, uint256 _value, bytes memory _data) payable {
        (bool success,) = _target.call{value: _value}(_data);
        require(success);
        factory = msg.sender;
    }

    function callAsOwner(bytes32 creationCode, address _target, uint256 _value, bytes memory _data) external {
        require(CallAndOwnFactory(factory).computeAddress(creationCode, msg.sender) == address(this));
        (bool success,) = _target.call{value: _value}(_data);
        require(success);
    }
}

contract CallAndOwnFactory {
    function call(address _owner, address _target, uint256 _value, bytes calldata _data) external payable {
        bytes32 salt = bytes32(uint256(uint160(_owner)));
        address callAndOwn = address(new CallAndOwn{salt: salt, value: _value}(_target, _value, _data));
        require(callAndOwn != address(0));
    }

    function computeAddress(bytes32 _creationCodeHash, address _owner) external view returns (address) {
        bytes32 salt = bytes32(uint256(uint160(_owner)));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, _creationCodeHash));
        return address(uint160(uint256(hash)));
    }
}
