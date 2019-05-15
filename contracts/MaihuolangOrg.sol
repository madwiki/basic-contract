pragma solidity >=0.4.25 <0.6.0;
import "./zeppelin-solidity/ECRecovery.sol";
import "./Owned.sol";
import { Token } from "./Token.sol";

contract MaihuolangOrg is Owned {
  Token mht;
  address public owner;
  address public rootUserAddr;
  address[] public restrictionProofs;
  uint public committeeRestriction = 8000000000000000000000;
  uint public rewardNonce;

  event UserChanged(address indexed _target, bool _placeholder);
  event CaseChanged(address indexed _buyer, address indexed _seller, uint8 _targetRank);

  mapping(address => User) public userMap;

  // 1: ready for upgrade, 2: upgraded
  mapping(address => uint8) public topRankPermissionMap;
  // buyer => seller => targetRank => Case
  mapping(address => mapping(address => mapping(uint8 => Case))) public caseMap;
  // buyer => seller
  mapping(address => mapping(address => bool)) public judgedApproval;
  struct Case {
    address arbiter;
    uint reviewToken;
    bool buyerComplainSeller;
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
    emit UserChanged(_rootUserAddr, true);
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
    require(userMap[_target].self == address(0));
    require(parentLevel <= 8, 'Level');
    require(childrenLength < 3, 'Children Full');

    userMap[_target].parent = _parent;
    userMap[_target].self = _target;
    userMap[_target].rank = parentLevel < 6 ? 9
    : parentLevel < 7
    ? 7
    : parentLevel < 8
    ? 4
    : 1;
    userMap[_target].level = parentLevel + 1;
    userMap[_target].rank1Delivered = 27;
    if (parentLevel < 7) {
      userMap[_target].rank1Received = 81;
    }
    userMap[_parent].children.push(_target);
    emit UserChanged(_target, true);
  }

  function committeeReview(
    address _buyer,
    address _seller,
    uint8 _targetRank,
    bool _shouldUpgrade,
    bool _shouldDowngrade,
    uint8[3] memory _types,
    uint8[5] memory _vArray,
    bytes32[5] memory _rArray,
    bytes32[5] memory _sArray
  ) public {
    uint totalToken;
    for (uint8 index = 0; index < _rArray.length; index++) {
      bytes32 reviewHash = reviewHashBuild(_buyer, _seller, _targetRank, _shouldUpgrade, _shouldDowngrade, _types);
      bytes32 hash = ECRecovery.toEthSignedMessageHash(reviewHash);
      address member = ecrecoverWrapper(hash, _vArray[index], _rArray[index], _sArray[index]);
      uint memberBalance = mht.balanceOf(member);
      require(memberBalance >= committeeRestriction, 'member balance');
      totalToken += memberBalance;
      mht.tokenIssue(member);
    }
    Case memory blockedCase = caseMap[_buyer][_seller][_targetRank];
    require(totalToken >= blockedCase.reviewToken, 'totalToken');
    caseMap[_buyer][_seller][_targetRank].reviewToken = totalToken;
    emit CaseChanged(_buyer, _seller, _targetRank);
    _changeStatusByType(_buyer, _types[0]);
    _changeStatusByType(_seller, _types[1]);
    _changeStatusByType(blockedCase.arbiter, _types[2]);
    if (_shouldUpgrade) {
      judgedApproval[_buyer][_seller] = true;
    }
    if (_shouldDowngrade) {
      if (blockedCase.buyerComplainSeller) {
        if (judgedApproval[_buyer][_seller]) {
          judgedApproval[_buyer][_seller] = false;
        } else {
          userMap[_buyer].rank -= 1;
          emit UserChanged(_buyer, true);
        }
      } else {
        userMap[_seller].frozen = true;
      }
    }
  }

  // function updateCommitteeRestriction(address[20] memory _proofs) public {
  //   require(msg.sender == owner || userMap[msg.sender].rank == 9);
  //   uint minBalance = mht.balanceOf(address(_proofs[0]));
  //   for (uint8 index = 1; index < _proofs.length; index++) {
  //     uint proofBalance = mht.balanceOf(address(_proofs[index]));
  //     if (proofBalance < minBalance) {
  //       minBalance = proofBalance;
  //     }
  //   }
  //   if (minBalance > committeeRestriction) {
  //     committeeRestriction = minBalance;
  //   } else if (restrictionProofs.length == 20) {
  //     for (uint8 index = 0; index < restrictionProofs.length; index++) {
  //       uint resProofBalance = mht.balanceOf(address(restrictionProofs[index]));
  //       if (resProofBalance < minBalance) {
  //         committeeRestriction = minBalance;
  //         restrictionProofs = _proofs;
  //         break;
  //       }
  //     }
  //   }
  // }

  function register(address _applicant, address _invitor, bytes memory _aplSig, bytes memory _invSig, bytes memory _mngSig) public {
    address parent = matchParent(_invitor);
    require(userMap[_applicant].self == address(0), 'Already');
    require(_registerCheck(_applicant, _invitor, parent, _aplSig, _invSig, _mngSig), 'Check Fail');
    userMap[_applicant].invitor = _invitor;
    userMap[_applicant].parent = parent;
    userMap[_applicant].self = _applicant;
    userMap[_applicant].rank = 1;
    userMap[_applicant].level = userMap[parent].level + 1;

    userMap[parent].children.push(_applicant);
  
    emit UserChanged(_applicant, true);
  }

  function registerForTopRank(address _applicant, address _invitor, address _preTop, bytes memory _aplSig, bytes memory _invSig, bytes memory _mngSig) public {
    register(_applicant, _invitor, _aplSig, _invSig, _mngSig);
    address targetPreTop = _applicant;
    for (uint16 index = 0; index < userMap[_applicant].level - userMap[_preTop].level; index++) {
      targetPreTop = userMap[targetPreTop].parent;
    }
    require(targetPreTop == _preTop, 'preTop');
    require(_relative(_preTop, _invitor) && (userMap[_invitor].level - userMap[_preTop].level >= 5), 'Invitor');

    uint8 preTopRankPermission = topRankPermissionMap[_preTop];
    if (preTopRankPermission != 0) {
      if (userMap[_preTop].rank == 8) {
        if (preTopRankPermission >= 3) {
          userMap[_preTop].rank = 9;
        } else {
          topRankPermissionMap[_preTop] = preTopRankPermission + 1;
        }
      }
    }
  }

  function lowRankUpgrade(address _applicant, bytes memory _aplSig, bytes memory _apvSig) public {
    require(_lowRankUpgradeCheck(_applicant, _aplSig, _apvSig), 'Check Fail');
    userMap[_applicant].rank += 1;
    emit UserChanged(_applicant, true);
  }

  function highRankUpgrade(address _applicant, bytes memory _aplSig, bytes memory _apvSig, bytes memory _mngSig) public {
    require(_highRankUpgradeCheck(_applicant, _aplSig, _apvSig, _mngSig), 'Check Fail');
    userMap[_applicant].rank += 1;
    emit UserChanged(_applicant, true);
  }

  function topRankPreUpgrade(address _applicant, bytes memory _aplSig, bytes memory _apvSig) public {
    require(_topRankPreUpgradeCheck(_applicant, _aplSig, _apvSig), 'Check Fail');
    topRankPermissionMap[_applicant] = 1;
  }

  function punishSeller (
    address _buyer,
    address _arbiter,
    address _seller,
    bytes memory _buyerSig,
    bytes memory _arbiterSig,
    uint8 _targetRank,
    bytes memory _tradeSig,
    uint8 _type,
    bool _shouldUpgrade
  ) public {
    require(_punishCheck(_buyer, _arbiter, _seller, _buyerSig, _arbiterSig, _targetRank, _tradeSig, _type, true));
    if (_shouldUpgrade && userMap[_buyer].rank < _targetRank) {
      judgedApproval[_buyer][_seller] = true;
    }
    _punishByType(_seller, _type);
    caseMap[_buyer][_seller][_targetRank] = Case(
      _arbiter,
      0,
      true
    );
    emit CaseChanged(_buyer, _seller, _targetRank);
  }

  function punishBuyer (
    address _seller,
    address _arbiter,
    address _buyer,
    bytes memory _sellerSig,
    bytes memory _arbiterSig,
    uint8 _targetRank,
    bytes memory _tradeSig,
    uint8 _type
  ) public {
    require(_punishCheck(_seller, _arbiter, _buyer, _sellerSig, _arbiterSig, _targetRank, _tradeSig, _type, false));
    _punishByType(_buyer, _type);
    caseMap[_buyer][_seller][_targetRank] = Case(
      _arbiter,
      0,
      false
    );
    emit CaseChanged(_buyer, _seller, _targetRank);
  }

  function _punishCheck (
    address _complainant,
    address _arbiter,
    address _respondent,
    bytes memory _comSig,
    bytes memory _arbSig,
    uint8 _targetRank,
    bytes memory _tradeSig,
    uint8 _type,
    bool _buyerComplainSeller
  ) private returns (bool) {
    User memory targetUser = userMap[_respondent];
    require(!isBlocked(_arbiter), 'arbiter blocked');
    require(userMap[_arbiter].rank >= 7, 'arbiter rank');
    require(targetUser.rank >= 1, 'rank');
    require(!_relative(_respondent, _arbiter), 'respondent relative');
    require(!_relative(_complainant, _arbiter), 'complainant relative');
    bytes32 tradeHash;
    if (_buyerComplainSeller) {
      require(caseMap[_complainant][_respondent][_targetRank].arbiter == address(0), 'case already exists');
      tradeHash = tradeHashBuild(_complainant, _respondent, _targetRank);
    } else {
      require(caseMap[_respondent][_complainant][_targetRank].arbiter == address(0), 'case already exists');
      tradeHash = tradeHashBuild(_respondent, _complainant, _targetRank);
    }
    bytes32 tHash = ECRecovery.toEthSignedMessageHash(tradeHash);
    require(_respondent == ECRecovery.recover(tHash, _tradeSig), 'trade sig');

    bytes32 punishmentHash = punishmentHashBuild(_respondent, _type);
    bytes32 pHash = ECRecovery.toEthSignedMessageHash(punishmentHash);
    require(_complainant == ECRecovery.recover(pHash, _comSig)
    && _arbiter == ECRecovery.recover(pHash, _arbSig), 'pHash sig');

    require(mht.tokenIssue(_arbiter), 'issue');
    return true;
  }

  function _changeStatusByType(address _target, uint8 _type) private {
    if (_type == 0) {
      userMap[_target].releaseAt = 0;
      userMap[_target].frozen = false;
      emit UserChanged(_target, true);
    } else {
      _punishByType(_target, _type);
    }
  }

  function _punishByType(address _target, uint8 _type) private {
    require(_type > 0);
    if (_type == 1) {
      userMap[_target].releaseAt = now + 7 days;
    } else if(_type == 2) {
      userMap[_target].releaseAt = now + 30 days;
    } else {
      userMap[_target].frozen = true;
    }
    emit UserChanged(_target, true);
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

    User memory upperOfLowerUser = lowerUser;
    for (uint16 index; index < lowerUser.level - higherUser.level; index++) {
      upperOfLowerUser = userMap[upperOfLowerUser.parent];
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

  function _registerCheck(address _applicant, address _invitor, address _parent, bytes memory _aplSig, bytes memory _invSig, bytes memory _mngSig) private returns (bool) {
    if (userMap[_applicant].rank != 0) {
      return false;
    }
    bytes32 upgradeHash = upgradeHashBuild(_applicant, 1);
    bytes32 hash = ECRecovery.toEthSignedMessageHash(upgradeHash);
    address manager = _getManagerWithUpdate(_applicant, _parent, 1);

    bool invitorApproval = judgedApproval[_applicant][_invitor];
    bool managerApproval = judgedApproval[_applicant][manager];
    if (invitorApproval) {
      judgedApproval[_applicant][_invitor] = false;
    }
    if (managerApproval) {
      judgedApproval[_applicant][manager] = false;
    }

    return _applicant == ECRecovery.recover(hash, _aplSig)
      && (invitorApproval || (_invitor == ECRecovery.recover(hash, _invSig) && _rewardByTx(_invitor)))
      && (managerApproval || (manager == ECRecovery.recover(hash, _mngSig) && _rewardByTx(manager)));
  }

  function _lowRankUpgradeCheck(address _applicant, bytes memory _aplSig, bytes memory _apvSig) private returns (bool) {
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

    bool approverApproval = judgedApproval[_applicant][approver];
    if (approverApproval) {
      judgedApproval[_applicant][approver] = false;
    }

    return _applicant == ECRecovery.recover(hash, _aplSig)
    && (approverApproval || (approver == ECRecovery.recover(hash, _apvSig) && _rewardByTx(approver)));
  }

  function _highRankUpgradeCheck(address _applicant, bytes memory _aplSig, bytes memory _apvSig, bytes memory _mngSig) private returns (bool) {
    User memory applicantUser = userMap[_applicant];
    if (applicantUser.rank < 4 || applicantUser.rank >= 8) {
      return false;
    }

    uint8 targetRank = applicantUser.rank + 1;

    bytes32 upgradeHash = upgradeHashBuild(_applicant, targetRank);
    bytes32 hash = ECRecovery.toEthSignedMessageHash(upgradeHash);
    address approver = getApprover(_applicant, targetRank);
    address manager = _getManagerWithUpdate(_applicant, applicantUser.parent, targetRank);

    bool approverApproval = judgedApproval[_applicant][approver];
    bool managerApproval = judgedApproval[_applicant][manager];
    if (approverApproval) {
      judgedApproval[_applicant][approver] = false;
    }
    if (managerApproval) {
      judgedApproval[_applicant][manager] = false;
    }

    return _applicant == ECRecovery.recover(hash, _aplSig)
      && (approverApproval || (approver == ECRecovery.recover(hash, _apvSig) && _rewardByTx(approver)))
      && (managerApproval || (manager == ECRecovery.recover(hash, _mngSig) && _rewardByTx(manager)));
  }

  function _topRankPreUpgradeCheck(address _applicant, bytes memory _aplSig, bytes memory _apvSig) private returns (bool) {
    User memory applicantUser = userMap[_applicant];
    if (applicantUser.rank != 8) {
      return false;
    }

    uint8 targetRank = applicantUser.rank + 1;

    bytes32 upgradeHash = upgradeHashBuild(_applicant, targetRank);
    bytes32 hash = ECRecovery.toEthSignedMessageHash(upgradeHash);
    address approver = getApprover(_applicant, targetRank);

    bool approverApproval = judgedApproval[_applicant][approver];
    if (approverApproval) {
      judgedApproval[_applicant][approver] = false;
    }

    return
      _applicant == ECRecovery.recover(hash, _aplSig)
      && (approverApproval || (approver == ECRecovery.recover(hash, _apvSig) && _rewardByTx(approver)))
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
    require(approverUser.rank >= 1, 'rank');
    uint16 count = 0;
    while(count < _targetRank || approverUser.rank < _targetRank || !_authority(_applicant, approverUser.self)) {
      if (approverUser.self == rootUserAddr) {
        return approverUser.self;
      }
      approverUser = userMap[approverUser.parent];
      count++;
    }
    return approverUser.self;
  }

  function _getManager(address _applicant, address _parent, uint8 _targetRank, bool _update) private returns (address) {
    require(_targetRank == 1 || (_targetRank >= 4 && _targetRank < 9));
    uint8 managerRank = _targetRank == 1
    ? 4
    : _targetRank < 7
    ? 7
    : 9;
    address manager = _parent;
    User memory managerUser = userMap[manager];

    if (managerRank == 4) {
      bool shouldPassToParent = true;

      while (shouldPassToParent) {
        if (managerUser.rank >= managerRank && managerUser.rank1Received < 81 && _authority(_applicant ,manager)) {
          User memory upperManager = managerUser;
          User memory childOfUpperManager = managerUser;
          require(upperManager.parent != address(0));
          upperManager = userMap[upperManager.parent];
          while (upperManager.rank < managerRank || !_authority(_applicant ,upperManager.self)) {
            childOfUpperManager = upperManager;
            upperManager = userMap[upperManager.parent];
          }
          if (childOfUpperManager.rank1Delivered >= 27) {
            shouldPassToParent = false;
            return manager;
          } else {
            manager = upperManager.self;
            if (_update) {
              userMap[childOfUpperManager.self].rank1Delivered += 1;
              userMap[manager].rank1Received += 1;
            }
            shouldPassToParent = false;
            return manager;
          }
        } else if (managerUser.self == rootUserAddr) {
          shouldPassToParent = false;
          return manager;
        }
        manager = managerUser.parent;
        managerUser = userMap[manager];
      }
    } else {
      uint8 count = 1;
      while ((count < managerRank && managerUser.self != rootUserAddr) || managerUser.rank < managerRank || !_authority(_applicant ,manager)) {
        count ++;
        manager = managerUser.parent;
        managerUser = userMap[manager];
      }
    }
    return manager;
  }

  function getManager(address _applicant, address _parent, uint8 _targetRank) public returns (address) {
    return _getManager(_applicant, _parent, _targetRank, false);
  }

  function _getManagerWithUpdate(address _applicant, address _parent, uint8 _targetRank) private returns (address) {
    return _getManager(_applicant, _parent, _targetRank, true);
  }

  function upgradeHashBuild(address _applicant, uint8 _targetRank) public pure returns (bytes32) {
    return keccak256(abi.encodePacked('upgrade', _applicant, _targetRank));
  }

  function tradeHashBuild(address _buyer, address _seller, uint16 _nonce) public pure returns (bytes32) {
    return keccak256(abi.encodePacked('trade', _buyer, _seller, _nonce));
  }

  function punishmentHashBuild(address _target, uint8 _type) public pure returns (bytes32) {
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
    uint tokens = rewardNonce < 5000000
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

  function _authority(address _applicant, address _auditor) private view returns (bool) {
    if (!isBlocked(_auditor)) {
      return true;
    } else {
      return judgedApproval[_applicant][_auditor];
    }
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

  function reviewHashBuild(
    address _buyer,
    address _seller,
    uint16 _targetRank,
    bool _shouldUpgrade,
    bool _shouldDowngrade,
    uint8[3] memory _types
  ) public pure returns (bytes32) {
    return keccak256(abi.encodePacked('review', _buyer, _seller, _targetRank, _shouldUpgrade, _shouldDowngrade, _types[0], _types[1], _types[2]));
  }

  function () external payable {
    revert();
  }
}
