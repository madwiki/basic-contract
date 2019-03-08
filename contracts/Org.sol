pragma solidity >=0.4.25 <0.6.0;
import "./zeppelin-solidity/ECRecovery.sol";
import "./Owned.sol";

contract Org is Owned {
  address public owner;
  address[] public rank9Arr;

  mapping (address => User) public userMap;
  struct User {
    address[] children;
    address parent;
    uint8 rank;
  }

  constructor() public {
    owner = msg.sender;
  }

  function register(address _applicant, address _invitor, bytes memory _sig0, bytes memory _sig1, bytes memory _sig2) public {
    address parent = _matchParent(_invitor);

    require(registerCheck(_applicant, parent, _sig0, _sig1, _sig2));
    userMap[_applicant].parent = parent;
    userMap[_applicant].rank = 1;
    userMap[parent].children.push(_applicant);
  }

  function _matchParent(address _invitor) private view returns (address) {
    address parent = _invitor;
    while (userMap[parent].children.length < 3) {
      parent = userMap[parent].children[0] <= userMap[parent].children[1] ?
      userMap[parent].children[0] : userMap[parent].children[1] <= userMap[parent].children[2]
      ? userMap[parent].children[1] : userMap[parent].children[2];
    }
    return parent;
  }

  function promote(address _applicant, bytes memory _sig0, bytes memory _sig1 ) public {
    require(promotionCheck(_applicant, _sig0, _sig1), 'Promotion Check failed!');
    userMap[_applicant].rank += 1;
  }

  function registerCheck(address _applicant, address _parent, bytes memory _sig0, bytes memory _sig1, bytes memory _sig2) public view returns (bool) {
    if (userMap[_applicant].rank != 0) {
      return false;
    }
    bytes32 promotionHash = promotionHashBuild(_applicant, 1);
    address officer = _getOfficer(_parent, 1);

    return _applicant == ECRecovery.recover(promotionHash, _sig0)
      && _parent == ECRecovery.recover(promotionHash, _sig1)
      && officer == ECRecovery.recover(promotionHash, _sig2);
  }

  function promotionCheck(address _applicant, bytes memory _sig0, bytes memory _sig1 ) public view returns (bool) {
    User storage applicantUser = userMap[_applicant];
    if (applicantUser.rank == 0) {
      return false;
    }

    uint8 targetRank = applicantUser.rank + 1;
    bytes32 promotionHash = promotionHashBuild(_applicant, targetRank);
    address approver = _getApprover(_applicant, targetRank);
    address officer = _getOfficer(_applicant, targetRank);

    return approver == ECRecovery.recover(promotionHash, _sig0)
      && officer == ECRecovery.recover(promotionHash, _sig1);
  }

  function _getApprover(address _applicant, uint8 _targetRank) private view returns (address) {
    address approver = _applicant;
    for (uint8 index = 1; index <= _targetRank; index++) {
      if (userMap[approver].parent == address(0)) {
        return approver;
      }
      approver = userMap[approver].parent;
    }
    return approver;
  }

  function _getOfficer(address _applicant, uint8 _targetRank) private view returns (address) {
    uint8 officerRank = _targetRank <= 4 ? 5 : 9;
    address officer = _applicant;
    while (userMap[officer].rank < officerRank) {
      officer = userMap[officer].parent;
    }
    return officer;
  }

  function promotionHashBuild(address _applicant, uint8 _targetRank) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(_applicant, _targetRank));
  }

}
