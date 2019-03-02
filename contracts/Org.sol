pragma solidity >=0.4.25 <0.6.0;

contract Org{
  address public owner;

  constructor() public {
    owner = msg.sender;
  }
}
