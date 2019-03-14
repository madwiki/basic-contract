pragma solidity >=0.4.25 <0.6.0;
import "./zeppelin-solidity/ECRecovery.sol";
import "./Owned.sol";

contract Org is Owned {
  address public owner;
  address public rootUserAddr;
  address[] public rank9Arr;

  mapping (address => User) public userMap;
  struct User {
    address[] children;
    address parent;
    address self;
    uint8 rank;
    uint16 level;
    bool frozen;
    uint rank1Received;
    uint rank1Delivered;
  }

  constructor() public {
    owner = msg.sender;
  }

  function register(address _applicant, address _invitor, bytes memory _sig0, bytes memory _sig1, bytes memory _sig2) public {
    address parent = _matchParent(_invitor);

    require(registerCheck(_applicant, parent, _sig0, _sig1, _sig2));
    userMap[_applicant].parent = parent;
    userMap[_applicant].self = _applicant;
    userMap[_applicant].rank = 1;
    userMap[_applicant].level = userMap[parent].level + 1;
    userMap[parent].children.push(_applicant);
  }

  function highRankPromote(address _applicant, bytes memory _sig0, bytes memory _sig1) public {
    require(_highRankPromotionCheck(_applicant, _sig0, _sig1), 'Promotion Check failed!');
    userMap[_applicant].rank += 1;
  }

  function lowRankPromote(address _applicant, bytes memory _sig0) public {
    require(_lowRankPromotionCheck(_applicant, _sig0), 'Promotion Check failed!');
    userMap[_applicant].rank += 1;
  }

  function freezeUser (
    address _targetAddr,
    address _complainant,
    address _arbiter,
    bytes memory _comSig,
    bytes memory _arbSig,
    bool _lowerSueHigher,
    bool _afterPromotion
  ) public {
    User memory targetUser = userMap[_targetAddr];
    User memory complainantUser = userMap[_complainant];
    require(targetUser.rank >= 1);
    require(!_relative(_targetAddr, _arbiter));
    require(!_relative(_complainant, _arbiter));
    if (_lowerSueHigher) {
      uint8 targetRank = _afterPromotion ? complainantUser.rank : complainantUser.rank + 1;
      require(_getApprover(_complainant, targetRank) == _targetAddr
        || getOfficer(_complainant, targetRank) == _targetAddr);
    } else {
      uint8 targetRank = _afterPromotion ? complainantUser.rank : complainantUser.rank + 1;
      require(_getApprover(_targetAddr, targetRank) == _complainant
        || getOfficer(_targetAddr, targetRank) == _complainant);
    }
    bytes32 freezeHash = freezeHashBuild(_complainant);
    require(_complainant == ECRecovery.recover(freezeHash, _comSig)
    && _arbiter == ECRecovery.recover(freezeHash, _arbSig));

    userMap[_targetAddr].frozen = true;
    if (_lowerSueHigher && !_afterPromotion) {
      userMap[_complainant].rank += 1;
    }
  }

  function unfreezeByCommittee() public {

  }

  function _relative(address _addr0, address _addr1) private returns (bool) {
    User memory lowerUser = userMap[_addr0];
    User memory higherUser = userMap[_addr1];

    if (lowerUser.level == higherUser.level) {
      return lowerUser.parent == higherUser.parent;
    } else if (lowerUser.level < higherUser.level) {
      User memory prevHigherUser = higherUser;
      higherUser = lowerUser;
      lowerUser = prevHigherUser;
    }
    User memory upperOfLowerUser = lowerUser;
    for (uint16 index; index < lowerUser.level - higherUser.level; index++) {
      upperOfLowerUser = userMap[lowerUser.parent];
    }
    return upperOfLowerUser.self == higherUser.self;
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

  function registerCheck(address _applicant, address _parent, bytes memory _sig0, bytes memory _sig1, bytes memory _sig2) public returns (bool) {
    if (userMap[_applicant].rank != 0) {
      return false;
    }
    bytes32 promotionHash = promotionHashBuild(_applicant, 1);
    address officer = _getOfficerWithModify(_parent, 1);

    return _applicant == ECRecovery.recover(promotionHash, _sig0)
      && _parent == ECRecovery.recover(promotionHash, _sig1)
      && officer == ECRecovery.recover(promotionHash, _sig2);
  }

  function _highRankPromotionCheck(address _applicant, bytes memory _sig0, bytes memory _sig1 ) private returns (bool) {
    User memory applicantUser = userMap[_applicant];
    if (applicantUser.rank < 4) {
      return false;
    }

    uint8 targetRank = applicantUser.rank + 1;

    if (targetRank == 5 && !checkRank1Count(_applicant, 81)) {
      return false;
    }

    bytes32 promotionHash = promotionHashBuild(_applicant, targetRank);
    address approver = _getApprover(_applicant, targetRank);
    address officer = _getOfficerWithModify(_applicant, targetRank);

    return approver == ECRecovery.recover(promotionHash, _sig0)
      && officer == ECRecovery.recover(promotionHash, _sig1);
  }

  function _lowRankPromotionCheck(address _applicant, bytes memory _sig0) private returns (bool) {
    User memory applicantUser = userMap[_applicant];
    if (applicantUser.rank == 0 ||applicantUser.rank >= 4) {
      return false;
    }

    uint8 targetRank = applicantUser.rank + 1;

    if (targetRank == 2 && applicantUser.children.length != 3) {
      return false;
    }

    bytes32 promotionHash = promotionHashBuild(_applicant, targetRank);
    address approver = _getApprover(_applicant, targetRank);

    return approver == ECRecovery.recover(promotionHash, _sig0);
  }

  function checkRank1Count(address _applicant, uint16 _targetCount) private view returns (bool) {
    uint16 count = 0;
    return _userLoop(userMap[_applicant], count, _targetCount) >= _targetCount;
  }

  function _userLoop(User memory _currentUser, uint16 _count, uint16 _targetCount) private view returns (uint16) {
    uint16 count = _count;
    if (_currentUser.children.length > 0) {
      for (uint8 index = 0; index < _currentUser.children.length; index++) {
        User memory childUser = userMap[_currentUser.children[index]];
        if (childUser.rank == 1) {
          count ++;
        }
        if (count >= _targetCount) {
          return count;
        }
        count = _userLoop(childUser, count, _targetCount);
      }
    }
    return count;
  }

  function _getApprover(address _applicant, uint8 _targetRank) private view returns (address) {
    User memory approverUser = userMap[_applicant];
    uint16 count = 0;
    while(count < _targetRank || approverUser.rank < _targetRank) {
      if (approverUser.self == rootUserAddr) {
        return approverUser.self;
      }
      approverUser = userMap[approverUser.parent];
      count++;
    }
    return approverUser.self;
  }

  function _getOfficerWithModify(address _applicant, uint8 _targetRank) private returns (address) {
    require(_targetRank == 1 || _targetRank >= 5);
    uint8 officerRank = _targetRank == 1 ? 5 : 9;
    address officer = _applicant;
    User memory officerUser = userMap[officer];

    if (officerRank == 5) {
      bool shouldPassToParent = true;

      while (shouldPassToParent) {
        officer = officerUser.parent;
        officerUser = userMap[officer];

        if (officerUser.rank >= officerRank && (officerUser.rank1Received < 243 || officerUser.self == rootUserAddr)) {
          User memory upperOfficer = officerUser;
          User memory childOfUpperOfficer = officerUser;
          upperOfficer = userMap[upperOfficer.parent];
          while (upperOfficer.rank < officerRank || upperOfficer.frozen) {
            childOfUpperOfficer = upperOfficer;
            upperOfficer = userMap[upperOfficer.parent];
          }
          if (childOfUpperOfficer.rank1Delivered >= 81) {
            shouldPassToParent = false;
          } else {
            userMap[childOfUpperOfficer.self].rank1Delivered += 1;
            officer = upperOfficer.self;
            userMap[officer].rank1Received += 1;
            shouldPassToParent = false;
          }
          shouldPassToParent = true;
        } else {
          shouldPassToParent = true;
        }
      }
    } else {
      uint8 count = 0;
      while (count < officerRank || officerUser.rank < officerRank || officerUser.frozen) {
        count ++;
        officerUser = userMap[officerUser.parent];
      }
    }
    return officer;
  }

  function getOfficer(address _applicant, uint8 _targetRank) public view returns (address) {
    require(_targetRank == 1 || _targetRank >= 5);
    uint8 officerRank = _targetRank == 1 ? 5 : 9;
    address officer = _applicant;
    User memory officerUser = userMap[officer];

    if (officerRank == 5) {
      bool shouldPassToParent = true;

      while (shouldPassToParent) {
        officer = officerUser.parent;
        officerUser = userMap[officer];

        if (officerUser.rank >= officerRank && (officerUser.rank1Received < 243 || officerUser.self == rootUserAddr)) {
          User memory upperOfficer = officerUser;
          User memory childOfUpperOfficer = officerUser;
          upperOfficer = userMap[upperOfficer.parent];
          while (upperOfficer.rank < officerRank || upperOfficer.frozen) {
            childOfUpperOfficer = upperOfficer;
            upperOfficer = userMap[upperOfficer.parent];
          }
          if (childOfUpperOfficer.rank1Delivered >= 81) {
            shouldPassToParent = false;
          } else {
            officer = upperOfficer.self;
            shouldPassToParent = false;
          }
          shouldPassToParent = true;
        } else {
          shouldPassToParent = true;
        }
      }
    } else {
      uint8 count = 0;
      while (count < officerRank || officerUser.rank < officerRank || officerUser.frozen) {
        count ++;
        officerUser = userMap[officerUser.parent];
      }
    }
    return officer;
  }

  function promotionHashBuild(address _applicant, uint8 _targetRank) public pure returns (bytes32) {
    return keccak256(abi.encodePacked('promotion', _applicant, _targetRank));
  }

  function freezeHashBuild(address _target) public pure returns (bytes32) {
    return keccak256(abi.encodePacked('freeze', _target));
  }

  function unfreezeHashBuild(address _target, uint8 _targetRank) public pure returns (bytes32) {
    return keccak256(abi.encodePacked('unfreeze', _target));
  }
}
