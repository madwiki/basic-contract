pragma solidity >=0.4.25 <0.6.0;
import "./zeppelin-solidity/ECRecovery.sol";
import "./Owned.sol";
import { Token } from "./Token.sol";

contract MaihuolangOrg is Owned {
  Token mht;
  address public owner;
  address public rootUserAddr;
  address[] public restrictionProofs;
  uint public committeeRestriction = 8000;
  uint public blockedNonce;
  uint public rewardNonce;

  mapping (address => User) public userMap;

  // 1: ready for upgrade, 2: upgraded
  mapping (address => uint8) public topRankPermissionMap;
  mapping (uint => BlockedHistory) public blockedMap;

  struct BlockedHistory {
    address target;
    address complainant;
    address arbiter;
    uint retrialToken;
    bool lowerSueHigher;
  }

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

  constructor(address _mht, address _rootUserAddr) public {
    owner = msg.sender;
    mht = Token(_mht);
    userMap[_rootUserAddr].self = _rootUserAddr;
    userMap[_rootUserAddr].rank = 9;
    userMap[_rootUserAddr].level = 1;
    userMap[_rootUserAddr].rank1Received = 81;
    userMap[_rootUserAddr].rank1Delivered = 27;
    rootUserAddr = _rootUserAddr;
  }

  function getChildren(address _userAddr) public view returns (address[] memory _children) {
    _children = userMap[_userAddr].children;
  }

  function getUserRank(address _userAddr) public view returns(uint8) {
    return userMap[_userAddr].rank;
  }

  function batchInitUsers(address[] memory _parents, address[] memory _targets) public onlyOwner {
    for (uint index = 0; index < _parents.length; index++) {
      initUser(_parents[index], _targets[index]);
    }
  }

  function initUser(address _parent, address _target) public onlyOwner {
    // can only set the user that the level <= 9
    uint16 parentLevel = userMap[_parent].level;
    uint childrenLength = userMap[_parent].children.length;
    require(userMap[_target].self == address(0), 'Already exists');
    require(parentLevel <= 8, 'Wrong level');
    require(childrenLength < 3, 'children is full');

    userMap[_target].parent = _parent;
    userMap[_target].self = _target;
    userMap[_target].rank = parentLevel < 5 ? 9
    : parentLevel < 7
    ? 7 : 5;
    userMap[_target].level = parentLevel + 1;
    userMap[_target].rank1Delivered = 27;
    if (parentLevel < 8) {
      userMap[_target].rank1Received = 81;
    }
    userMap[_parent].children.push(_target);
  }

  function committeeRetrial(
    uint _nonce,
    bool _shouldUpgrade,
    bool _shouldDowngrade,
    bool _punishment,
    uint8[3] memory _types,
    uint8[5] memory _vArray,
    bytes32[5] memory _rArray,
    bytes32[5] memory _sArray
  ) public {
    uint totalToken;
    for (uint8 index = 0; index < _rArray.length; index++) {
      bytes32 freezeHash = retrialHashBuild(_nonce, _shouldUpgrade, _shouldDowngrade, _punishment, _types);
      bytes32 hash = ECRecovery.toEthSignedMessageHash(freezeHash);
      address member = ecrecoverWrapper(hash, _vArray[index], _rArray[index], _sArray[index]);
      totalToken += mht.balanceOf(member);
      mht.tokenIssue(member);
    }
    BlockedHistory memory frozenHistory = blockedMap[_nonce];
    require(totalToken >= frozenHistory.retrialToken, 'token not enough');
    _changeStatusByType(frozenHistory.target, _types[0]);
    _changeStatusByType(frozenHistory.complainant, _types[1]);
    _changeStatusByType(frozenHistory.arbiter, _types[2]);
    if (_shouldUpgrade) {
      if (frozenHistory.lowerSueHigher) {
        userMap[frozenHistory.complainant].rank += 1;
      } else {
        userMap[frozenHistory.target].rank += 1;
      }
    }
    if (_shouldDowngrade) {
      if (frozenHistory.lowerSueHigher) {
        userMap[frozenHistory.complainant].rank -= 1;
      } else {
        require(userMap[frozenHistory.target].rank >= 1, 'can not downgrade the rank1 user');
        userMap[frozenHistory.target].rank -= 1;
      }
    }
  }

  function updateCommitteeRestriction(address[20] memory _proofs) public {
    require(msg.sender == owner || userMap[msg.sender].rank == 9);
    uint minBalance = mht.balanceOf(address(_proofs[0]));
    for (uint8 index = 1; index < _proofs.length; index++) {
      uint proofBalance = mht.balanceOf(address(_proofs[index]));
      if (proofBalance < minBalance) {
        minBalance = proofBalance;
      }
    }
    if (minBalance > committeeRestriction) {
      committeeRestriction = minBalance;
    } else if (restrictionProofs.length == 20) {
      for (uint8 index = 0; index < restrictionProofs.length; index++) {
        uint resProofBalance = mht.balanceOf(address(restrictionProofs[index]));
        if (resProofBalance < minBalance) {
          committeeRestriction = minBalance;
          restrictionProofs = _proofs;
          break;
        }
      }
    }
  }

  function batchUpdate (
    address[] memory _registerApplicants,
    address[] memory _registerInvitors,
    uint8[3][] memory _vRegisterArray,
    bytes32[3][] memory _rRegisterArray,
    bytes32[3][] memory _sRegisterArray,
    address[] memory _lowRankApplicants,
    uint8[2][] memory _vLowRankArray,
    bytes32[2][] memory _rLowRankArray,
    bytes32[2][] memory _sLowRankArray,
    address[] memory _highRankApplicants,
    uint8[3][] memory _vHighRankArray,
    bytes32[3][] memory _rHighRankArray,
    bytes32[3][] memory _sHighRankArray
  ) public {
    for (uint i = 0; i < _registerApplicants.length; i++) {
      register(_registerApplicants[i], _registerInvitors[i], _vRegisterArray[i], _rRegisterArray[i], _sRegisterArray[i]);
    }
    for (uint i = 0; i < _lowRankApplicants.length; i++) {
      lowRankUpgrade(_lowRankApplicants[i], _vLowRankArray[i], _rLowRankArray[i], _sLowRankArray[i]);
    }
    for (uint i = 0; i < _highRankApplicants.length; i++) {
      highRankUpgrade(_highRankApplicants[i], _vHighRankArray[i], _rHighRankArray[i], _sHighRankArray[i]);
    }
  }

  function register(address _applicant, address _invitor, uint8[3] memory _vArray, bytes32[3] memory _rArray, bytes32[3] memory _sArray) public {
    address parent = matchParent(_invitor);
    require(userMap[_applicant].self == address(0), 'already registered');
    require(_registerCheck(_applicant, _invitor, parent, _vArray, _rArray, _sArray), 'check fail');
    userMap[_applicant].parent = parent;
    userMap[_applicant].self = _applicant;
    userMap[_applicant].rank = 1;
    userMap[_applicant].level = userMap[parent].level + 1;

    userMap[parent].children.push(_applicant);
    
    uint8 preTopRankPermission = topRankPermissionMap[_invitor];
    if (preTopRankPermission != 0) {
      if (userMap[_invitor].rank == 8) {
        if (preTopRankPermission >= 3) {
          userMap[_invitor].rank = 9;
        } else {
          topRankPermissionMap[_invitor] = preTopRankPermission + 1;
        }
      }
      
    }
  }

  function lowRankUpgrade(address _applicant, uint8[2] memory _vArray, bytes32[2] memory _rArray, bytes32[2] memory _sArray) public {
    require(_lowRankUpgradeCheck(_applicant, _vArray, _rArray, _sArray), 'Upgrade Check failed');
    userMap[_applicant].rank += 1;
  }

  function highRankUpgrade(address _applicant, uint8[3] memory _vArray, bytes32[3] memory _rArray, bytes32[3] memory _sArray) public {
    require(_highRankUpgradeCheck(_applicant, _vArray, _rArray, _sArray), 'Upgrade Check failed');
    userMap[_applicant].rank += 1;
  }

  function topRankPreUpgrade(address _applicant, uint8[2] memory _vArray, bytes32[2] memory _rArray, bytes32[2] memory _sArray) public {
    require(_topRankPreUpgradeCheck(_applicant, _vArray, _rArray, _sArray), 'Upgrade Check failed');
    topRankPermissionMap[_applicant] = 1;
  }

  function freezeUser (
    address _target,
    address _complainant,
    address _arbiter,
    bytes memory _comSig,
    bytes memory _arbSig,
    bool _lowerSueHigher,
    bool _shouldUpgrade,
    uint8 _type
  ) public {
    User memory targetUser = userMap[_target];
    User memory complainantUser = userMap[_complainant];
    require(_type != 0, '0 is not a kind of freezing type');
    require(targetUser.rank >= 1, 'rank should >= 1');
    require((_lowerSueHigher && targetUser.rank > complainantUser.rank)
    || (!_lowerSueHigher && targetUser.rank < complainantUser.rank),
    'wrong value of lowerSueHigher');
    // require(!_relative(_target, _arbiter), 'target and arbiter are relative');
    require(!_relative(_complainant, _arbiter), 'complainant and arbiter are relative');
    if (_lowerSueHigher) {
      uint8 targetRank = _shouldUpgrade ? complainantUser.rank + 1 : complainantUser.rank;
      require(getApprover(_complainant, targetRank) == _target
        || getOfficer(_complainant, targetRank) == _target);
    } else {
      uint8 targetRank = _shouldUpgrade ? complainantUser.rank + 1 : complainantUser.rank;
      require(getApprover(_target, targetRank) == _complainant
        || getOfficer(_target, targetRank) == _complainant);
    }
    bytes32 freezeHash = freezeHashBuild(_target, _type);
    bytes32 hash = ECRecovery.toEthSignedMessageHash(freezeHash);
    require(_complainant == ECRecovery.recover(hash, _comSig)
    && _arbiter == ECRecovery.recover(hash, _arbSig)
    && mht.tokenIssue(_arbiter));

    if (_lowerSueHigher && !_shouldUpgrade) {
      userMap[_complainant].rank += 1;
    }
  
    _changeStatusByType(_target, _type);

    blockedMap[blockedNonce] = BlockedHistory(
      _target,
      _complainant,
      _arbiter,
      0,
      _lowerSueHigher
    );
    blockedNonce ++;
  }

  function _changeStatusByType(address _target, uint8 _type) private {
    if (_type == 0) {
      userMap[_target].releaseAt = 0;
      userMap[_target].frozen = false;
    } else if (_type == 1) {
      userMap[_target].releaseAt = now + 7 days;
    } else if(_type == 2) {
      userMap[_target].releaseAt = now + 30 days;
    } else {
      userMap[_target].frozen = true;
    }
  }

  function _relative(address _addr0, address _addr1) private view returns (bool) {
    User memory lowerUser = userMap[_addr0];
    User memory higherUser = userMap[_addr1];

    if (lowerUser.level == higherUser.level) {
      return lowerUser.parent == higherUser.parent;
    } else if (lowerUser.level < higherUser.level) {
      User memory preHigherUser = higherUser;
      higherUser = lowerUser;
      lowerUser = preHigherUser;
    }
    require(lowerUser.level > higherUser.level, 'xxxx');
    User memory upperOfLowerUser = lowerUser;
    for (uint16 index; index < lowerUser.level - higherUser.level; index++) {
      upperOfLowerUser = userMap[lowerUser.parent];
    }
    return upperOfLowerUser.self == higherUser.self;
  }

  function matchParent(address _invitor) public view returns (address) {
    address parent = _invitor;
    while (userMap[parent].children.length == 3) {
      parent = userMap[userMap[parent].children[2]].children.length < userMap[userMap[parent].children[1]].children.length ?
      userMap[parent].children[2] : userMap[userMap[parent].children[1]].children.length < userMap[userMap[parent].children[0]].children.length
      ? userMap[parent].children[1] : userMap[parent].children[0];
    }
    return parent;
  }

  function _registerCheck(address _applicant, address _invitor, address _parent, uint8[3] memory _vArray, bytes32[3] memory _rArray, bytes32[3] memory _sArray) private returns (bool) {
    if (userMap[_applicant].rank != 0) {
      return false;
    }
    bytes32 upgradeHash = upgradeHashBuild(_applicant, 1);
    bytes32 hash = ECRecovery.toEthSignedMessageHash(upgradeHash);
    address officer = _getOfficerWithModify(_parent, 1);

    return _applicant == ecrecoverWrapper(hash, _vArray[0], _rArray[0], _sArray[0])
      && _invitor == ecrecoverWrapper(hash, _vArray[1], _rArray[1], _sArray[1])
      && officer == ecrecoverWrapper(hash, _vArray[2], _rArray[2], _sArray[2])
      && _rewardByTx(_invitor)
      && _rewardByTx(officer);
  }

  function _lowRankUpgradeCheck(address _applicant, uint8[2] memory _vArray, bytes32[2] memory _rArray, bytes32[2] memory _sArray) private returns (bool) {
    User memory applicantUser = userMap[_applicant];
    if (applicantUser.rank == 0 || applicantUser.rank >= 4) {
      return false;
    }

    uint8 targetRank = applicantUser.rank + 1;

    if (targetRank == 2 && applicantUser.children.length != 3) {
      return false;
    }

    if (targetRank == 4 && !checkLowerLevelCount(_applicant, 27)) {
      return false;
    }

    bytes32 upgradeHash = upgradeHashBuild(_applicant, targetRank);
    bytes32 hash = ECRecovery.toEthSignedMessageHash(upgradeHash);
    address approver = getApprover(_applicant, targetRank);

    return
    _applicant == ecrecoverWrapper(hash, _vArray[0], _rArray[0], _sArray[0])
    && approver == ecrecoverWrapper(hash, _vArray[1], _rArray[1], _sArray[1])
    && _rewardByTx(approver);
  }

  function _highRankUpgradeCheck(address _applicant, uint8[3] memory _vArray, bytes32[3] memory _rArray, bytes32[3] memory _sArray) private returns (bool) {
    User memory applicantUser = userMap[_applicant];
    if (applicantUser.rank < 4 || applicantUser.rank >= 8) {
      return false;
    }

    uint8 targetRank = applicantUser.rank + 1;

    bytes32 upgradeHash = upgradeHashBuild(_applicant, targetRank);
    bytes32 hash = ECRecovery.toEthSignedMessageHash(upgradeHash);
    address approver = getApprover(_applicant, targetRank);
    address officer = _getOfficerWithModify(applicantUser.parent, targetRank);

    return
      _applicant == ecrecoverWrapper(hash, _vArray[0], _rArray[0], _sArray[0])
      && approver == ecrecoverWrapper(hash, _vArray[1], _rArray[1], _sArray[1])
      && officer == ecrecoverWrapper(hash, _vArray[2], _rArray[2], _sArray[2])
      && _rewardByTx(approver)
      && _rewardByTx(officer);
  }

  function _topRankPreUpgradeCheck(address _applicant, uint8[2] memory _vArray, bytes32[2] memory _rArray, bytes32[2] memory _sArray) private returns (bool) {
    User memory applicantUser = userMap[_applicant];
    if (applicantUser.rank != 8) {
      return false;
    }

    uint8 targetRank = applicantUser.rank + 1;

    bytes32 upgradeHash = upgradeHashBuild(_applicant, targetRank);
    bytes32 hash = ECRecovery.toEthSignedMessageHash(upgradeHash);
    address approver = getApprover(_applicant, targetRank);

    return
      _applicant == ecrecoverWrapper(hash, _vArray[0], _rArray[0], _sArray[0])
      && approver == ecrecoverWrapper(hash, _vArray[1], _rArray[1], _sArray[1])
      && _rewardByTx(approver);
  }

  function checkLowerLevelCount(address _applicant, uint16 _targetCount) public view returns (bool) {
    uint16 count = 0;
    return _userLoop(userMap[_applicant], count, _targetCount) >= _targetCount;
  }

  function _userLoop(User memory _currentUser, uint16 _count, uint16 _targetCount) private view returns (uint16) {
    uint16 count = _count;
    if (_currentUser.children.length > 0) {
      for (uint8 index = 0; index < _currentUser.children.length; index++) {
        User memory childUser = userMap[_currentUser.children[index]];
        if (childUser.rank >= 1) {
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

  function getApprover(address _applicant, uint8 _targetRank) public view returns (address) {
    User memory approverUser = userMap[_applicant];
    require(approverUser.rank >= 1, 'Rank needed');
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

  function _getOfficerWithModify(address _parent, uint8 _targetRank) private returns (address) {
    require(_targetRank == 1 || (_targetRank >= 4 && _targetRank < 9));
    uint8 officerRank = _targetRank == 1
    ? 4
    : _targetRank < 7
    ? 7
    : 9;
    address officer = _parent;
    User memory officerUser = userMap[officer];

    if (officerRank == 4) {
      bool shouldPassToParent = true;

      while (shouldPassToParent) {
        if (officerUser.rank >= officerRank && officerUser.rank1Received < 81 && !isBlocked(officer)) {
          User memory upperOfficer = officerUser;
          User memory childOfUpperOfficer = officerUser;
          require(upperOfficer.parent != address(0), 'address can not be null');
          upperOfficer = userMap[upperOfficer.parent];
          while (upperOfficer.rank < officerRank || isBlocked(upperOfficer.self)) {
            childOfUpperOfficer = upperOfficer;
            upperOfficer = userMap[upperOfficer.parent];
          }
          if (childOfUpperOfficer.rank1Delivered >= 27) {
            shouldPassToParent = false;
            return officer;
          } else {
            userMap[childOfUpperOfficer.self].rank1Delivered += 1;
            officer = upperOfficer.self;
            userMap[officer].rank1Received += 1;
            shouldPassToParent = false;
            return officer;
          }
        } else if (officerUser.self == rootUserAddr) {
          shouldPassToParent = false;
          return officer;
        }
        officer = officerUser.parent;
        officerUser = userMap[officer];
      }
    } else {
      uint8 count = 1;
      while ((count < officerRank && officerUser.self != rootUserAddr) || officerUser.rank < officerRank || isBlocked(officer)) {
        count ++;
        officer = officerUser.parent;
        officerUser = userMap[officer];
      }
    }
    return officer;
  }

  function getOfficer(address _parent, uint8 _targetRank) public view returns (address) {
    require(_targetRank == 1 || (_targetRank >= 4 && _targetRank < 9));
    uint8 officerRank = _targetRank == 1
    ? 4
    : _targetRank < 7
    ? 7
    : 9;
    address officer = _parent;
    User memory officerUser = userMap[officer];

    if (officerRank == 4) {
      bool shouldPassToParent = true;

      while (shouldPassToParent) {
        if (officerUser.rank >= officerRank && officerUser.rank1Received < 81 && !isBlocked(officer)) {
          User memory upperOfficer = officerUser;
          User memory childOfUpperOfficer = officerUser;
          require(upperOfficer.parent != address(0), 'address can not be null');
          upperOfficer = userMap[upperOfficer.parent];
          while (upperOfficer.rank < officerRank || isBlocked(upperOfficer.self)) {
            childOfUpperOfficer = upperOfficer;
            upperOfficer = userMap[upperOfficer.parent];
          }
          if (childOfUpperOfficer.rank1Delivered >= 27) {
            shouldPassToParent = false;
            return officer;
          } else {
            officer = upperOfficer.self;
            shouldPassToParent = false;
            return officer;
          }
        } else if (officerUser.self == rootUserAddr) {
          shouldPassToParent = false;
          return officer;
        }
        officer = officerUser.parent;
        officerUser = userMap[officer];
      }
    } else {
      uint8 count = 1;
      while ((count < officerRank && officerUser.self != rootUserAddr) || officerUser.rank < officerRank || isBlocked(officer)) {
        count ++;
        officer = officerUser.parent;
        officerUser = userMap[officer];
      }
    }
    return officer;
  }

  function upgradeHashBuild(address _applicant, uint8 _targetRank) public pure returns (bytes32) {
    return keccak256(abi.encodePacked('upgrade', _applicant, _targetRank));
  }

  function freezeHashBuild(address _target, uint8 _type) public pure returns (bytes32) {
    if (_type == 1) {
      return keccak256(abi.encodePacked('7Dfreeze', _target));
    } else if (_type == 2) {
      return keccak256(abi.encodePacked('30Dfreeze', _target));
    } else {
      return keccak256(abi.encodePacked('freeze', _target));
    }
  }

  function _rewardByTx(address _userAddr) private returns (bool) {
    uint balance = mht.balanceOf(address(this));
    if (balance == 0) {
      return true;
    }
    uint tokens = rewardNonce < 2000000
      ? 20000000000000000000
      : rewardNonce < 20000000
      ? 10000000000000000000
      : rewardNonce < 50000000
      ? 5000000000000000000
      : rewardNonce < 120000000
      ? 2500000000000000000
      : 1250000000000000000;

    if (tokens < balance) {
      require(mht.transfer(_userAddr, tokens), 'token transferred');
    } else {
      require(mht.transfer(_userAddr, balance), 'token transferred');
    }
    rewardNonce ++;
    return true;
  }

  function isBlocked(address _userAddr) public view returns (bool) {
    User memory user = userMap[_userAddr];
    return user.releaseAt > 0 ? (user.releaseAt > now || user.frozen) : user.frozen;
  }

  function ecrecoverWrapper (bytes32 _hash, uint8 _v, bytes32 _r, bytes32 _s)
    internal
    pure
    returns (address)
  {
    // Version of signature should be 27 or 28, but 0 and 1 are also possible versions
    uint8 v = _v < 27 ? _v + 27 :_v;

    // If the version is correct return the signer address
    if (v != 27 && v != 28) {
      return (address(0));
    } else {
      return ecrecover(_hash, v, _r, _s);
    }
  }

  function retrialHashBuild(
    uint _nonce,
    bool _shouldUpgrade,
    bool _shouldDowngrade,
    bool _punishment,
    uint8[3] memory _types
  ) public pure returns (bytes32) {
    return keccak256(abi.encodePacked('retrial', _nonce, _shouldUpgrade, _shouldDowngrade, _punishment, _types[0], _types[1], _types[2]));
  }

  function () external payable {
    revert();
  }
}
