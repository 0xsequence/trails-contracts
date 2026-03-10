// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

contract Emitter {
  event Emitted(address sender, bytes data, uint256 value);

  function doEmit(bytes calldata data) external payable {
    emit Emitted(msg.sender, data, msg.value);
  }
}

contract RecordingReceiver {
  bytes public lastData;
  uint256 public lastValue;
  address public lastSender;
  uint256 public calls;

  function reset() external {
    delete lastData;
    lastValue = 0;
    lastSender = address(0);
    calls = 0;
  }

  fallback() external payable {
    lastData = msg.data;
    lastValue = msg.value;
    lastSender = msg.sender;
    calls++;
  }

  receive() external payable {
    lastData = "";
    lastValue = msg.value;
    lastSender = msg.sender;
    calls++;
  }
}

contract RevertingReceiver {
  fallback() external payable {
    revert("revert");
  }

  receive() external payable {
    revert("revert");
  }
}

contract RejectEther {
  receive() external payable {
    revert("no-eth");
  }
}

contract MockERC20 {
  string public name = "MockERC20";
  string public symbol = "M20";
  uint8 public decimals = 18;

  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    uint256 bal = balanceOf[msg.sender];
    require(bal >= amount, "insufficient");
    unchecked {
      balanceOf[msg.sender] = bal - amount;
    }
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    uint256 allowed = allowance[from][msg.sender];
    require(allowed >= amount, "allowance");
    uint256 bal = balanceOf[from];
    require(bal >= amount, "insufficient");

    unchecked {
      allowance[from][msg.sender] = allowed - amount;
      balanceOf[from] = bal - amount;
    }
    balanceOf[to] += amount;
    return true;
  }
}

contract MockMetadataProbeToken {
  bytes4 private constant NAME_SELECTOR = 0x06fdde03;
  bytes4 private constant SYMBOL_SELECTOR = 0x95d89b41;

  enum MetadataBehavior {
    StringNonZero,
    StringEmpty,
    Bytes32NonZero,
    Bytes32Zero,
    Revert,
    Malformed
  }

  MetadataBehavior public immutable nameBehavior;
  MetadataBehavior public immutable symbolBehavior;

  constructor(MetadataBehavior _nameBehavior, MetadataBehavior _symbolBehavior) {
    nameBehavior = _nameBehavior;
    symbolBehavior = _symbolBehavior;
  }

  function transfer(address, uint256) external pure returns (bool) {
    return true;
  }

  fallback() external payable {
    bytes4 selector = msg.sig;

    if (selector == NAME_SELECTOR) _returnMetadata(nameBehavior, false);
    if (selector == SYMBOL_SELECTOR) _returnMetadata(symbolBehavior, true);

    revert("unknown-selector");
  }

  function _returnMetadata(MetadataBehavior _behavior, bool _isSymbol) internal pure {
    if (_behavior == MetadataBehavior.Revert) revert("metadata");

    if (_behavior == MetadataBehavior.Bytes32Zero) {
      assembly {
        mstore(0x00, 0)
        return(0x00, 0x20)
      }
    }

    if (_behavior == MetadataBehavior.Bytes32NonZero) {
      bytes32 word = _isSymbol ? bytes32("SYM") : bytes32("Mock Metadata");
      assembly {
        mstore(0x00, word)
        return(0x00, 0x20)
      }
    }

    bytes memory response;
    if (_behavior == MetadataBehavior.StringEmpty) {
      response = abi.encode("");
    } else if (_behavior == MetadataBehavior.StringNonZero) {
      response = abi.encode(_isSymbol ? "SYM" : "Mock Metadata");
    } else {
      response = hex"1234";
    }

    assembly {
      return(add(response, 0x20), mload(response))
    }
  }
}

contract MockERC721 {
  mapping(uint256 => address) public ownerOf;
  mapping(uint256 => address) public getApproved;
  mapping(address => mapping(address => bool)) public isApprovedForAll;

  function setOwner(uint256 tokenId, address owner) external {
    ownerOf[tokenId] = owner;
  }

  function setApproved(uint256 tokenId, address spender) external {
    getApproved[tokenId] = spender;
  }

  function setApprovedForAll(address owner, address operator, bool approved) external {
    isApprovedForAll[owner][operator] = approved;
  }
}

contract MockERC1155 {
  mapping(address => mapping(uint256 => uint256)) public balanceOf;
  mapping(address => mapping(address => bool)) public isApprovedForAll;

  function mint(address to, uint256 tokenId, uint256 amount) external {
    balanceOf[to][tokenId] += amount;
  }

  function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
    external
    view
    returns (uint256[] memory balances)
  {
    require(accounts.length == ids.length, "len");
    balances = new uint256[](accounts.length);
    for (uint256 i = 0; i < accounts.length; i++) {
      balances[i] = balanceOf[accounts[i]][ids[i]];
    }
  }

  function setApprovedForAll(address owner, address operator, bool approved) external {
    isApprovedForAll[owner][operator] = approved;
  }
}
