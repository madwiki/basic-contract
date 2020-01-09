pragma solidity >=0.4.25 <0.6.0;

contract Org {
  struct User {
    address[] children;
    address parent;
    address self;
    address invitor;
    uint8 rank;
    uint16 level;
    bool frozen;
    uint releaseAt;
    uint rank1Received;
    uint rank1Delivered;
  }
  address public rootUserAddr;
  uint public rewardNonce;
  function getUserRank(address _userAddr) public returns(uint8) {}
  mapping(address => User) public userMap;
  mapping(address => uint8) public topRankPermissionMap;
  function getChildren(address _userAddr) public view returns (address[] memory _children) {}
}
