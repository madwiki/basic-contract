pragma solidity >=0.4.25 <0.6.0;

contract Org {

  function getUserRank(address _userAddr) public returns(uint8) {}

  function committeeRetrial(
    uint _nonce,
    bool _shouldUpgrade,
    bool _shouldDowngrade,
    bool _punishment,
    uint8[3] memory _types,
    uint8[5] memory _vArray,
    bytes32[5] memory _rArray,
    bytes32[5] memory _sArray
  ) public {}

  function updateCommitteeRestriction(address[20] memory _proofs) public {}

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
  ) public {}

  function register(address _applicant, address _invitor, uint8[3] memory _vArray, bytes32[3] memory _rArray, bytes32[3] memory _sArray) public {}

  function lowRankUpgrade(address _applicant, uint8[2] memory _vArray, bytes32[2] memory _rArray, bytes32[2] memory _sArray) public {}

  function highRankUpgrade(address _applicant, uint8[3] memory _vArray, bytes32[3] memory _rArray, bytes32[3] memory _sArray) public {}

  function freezeUser (
    address _targetAddr,
    address _complainant,
    address _arbiter,
    bytes memory _comSig,
    bytes memory _arbSig,
    bool _lowerSueHigher,
    bool _shouldUpgrade,
    uint8 _type
  ) public {}

  function getOfficer(address _applicant, uint8 _targetRank) public view returns (address) {}

  function upgradeHashBuild(address _applicant, uint8 _targetRank) public pure returns (bytes32) {}

  function freezeHashBuild(address _target, uint8 _type) public pure returns (bytes32) {}

  function isBlocked(address _userAddr) public view returns (bool) {}

  function retrialHashBuild(
    uint _nonce,
    bool _shouldUpgrade,
    bool _shouldDowngrade,
    bool _punishment,
    uint8[3] memory _types
  ) public pure returns (bytes32) {}
}
