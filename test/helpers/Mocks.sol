// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

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

contract MockERC721 {
  mapping(uint256 => address) public getApproved;
  mapping(address => mapping(address => bool)) public isApprovedForAll;

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

