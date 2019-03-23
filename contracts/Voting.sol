pragma solidity >=0.4.25 <0.6.0;
import "./Owned.sol";
import "./zeppelin-solidity/ECRecovery.sol";
import "./zeppelin-solidity/SafeMath.sol";
import { Token } from "./Token.sol";
import { Org } from "./org.sol";


/**
 * Voting contract
 */
contract Voting is Owned {
  using SafeMath for uint;

  Token mht;
  Org org;
  uint public projectNonce;
  mapping (uint => Project) public projectMap;
  mapping (uint => uint) public bidNonceMap;
  mapping (uint => mapping (address => Bid)) bidMap;
  mapping (uint => mapping (address => address)) voterChoiceMap;
  mapping (uint => mapping (address => uint8)) voterRewardStatusMap;
  mapping (uint => mapping (address => uint)) votesMap;
  mapping (uint => address) public projectResultMap;

  struct Project {
    address sponsor;
    string name;
    uint deadline;
    uint voters;
    address[] bids;
  }

  struct Bid {
    string name;
    uint token;
  }

  constructor(address _mht, address _org) public {
    owner = msg.sender;
    mht = Token(_mht);
    org = Org(_org);
  }

  function createProject (string memory _name, uint _deadline) public {
    projectMap[projectNonce].sponsor = msg.sender;
    projectMap[projectNonce].name = _name;
    projectMap[projectNonce].deadline = _deadline;
    projectNonce ++;
  }

  function _bid(
    address _bidder,
    uint _projectNonce,
    string memory _name,
    bytes memory _transferSignature,
    uint _tokens,
    uint _txNonce
  ) private returns (bool) {
    require(_tokens > 0, 'tokens cant be 0');
    require(bidMap[_projectNonce][_bidder].token == 0, 'already bid');
    require(org.getUserRank(_bidder) >= 4, 'incorrect rank');
    require(mht.delegatedTransfer(_transferSignature, address(this), _tokens, 0, _txNonce));
    bidMap[_projectNonce][_bidder] = Bid(_name, _tokens);
    projectMap[_projectNonce].bids.push(_bidder);
    return true;
  }

  function bid(
    uint _projectNonce,
    string memory _name,
    bytes memory _transferSignature,
    uint _tokens,
    uint _txNonce
  ) public {
    _bid(msg.sender, _projectNonce, _name, _transferSignature, _tokens, _txNonce);
  }

  function delegatedBid(
    address _bidder,
    uint _fee,
    uint _projectNonce,
    string memory _name,
    bytes memory _feeSignature,
    bytes memory _transferSignature,
    uint _tokens,
    uint _txNonce
  ) public {
    require(mht.delegatedTransfer(_feeSignature, msg.sender, _fee, 0, _txNonce));
    _bid(_bidder, _projectNonce, _name, _transferSignature, _tokens, _txNonce);
  }

  function _additionalToken(
    address _bidder,
    uint _projectNonce,
    bytes memory _transferSignature,
    uint _tokens,
    uint _txNonce
  ) private {
    require(_tokens > 0, 'tokens cant be 0');
    require(org.getUserRank(_bidder) >= 4, 'incorrect rank');
    require(mht.delegatedTransfer(_transferSignature, address(this), _tokens, 0, _txNonce));
    bidMap[_projectNonce][_bidder].token = bidMap[_projectNonce][_bidder].token.add(_tokens);
  }

  function additionalToken(
    uint _projectNonce,
    bytes memory _transferSignature,
    uint _tokens,
    uint _txNonce
  ) public {
    _additionalToken(msg.sender, _projectNonce, _transferSignature, _tokens, _txNonce);
  }

  function delegatedAdditionalToken(
    address _bidder,
    uint _fee,
    uint _projectNonce,
    bytes memory _feeSignature,
    bytes memory _transferSignature,
    uint _tokens,
    uint _txNonce
  ) public {
    require(mht.delegatedTransfer(_feeSignature, msg.sender, _fee, 0, _txNonce));
    _additionalToken(_bidder, _projectNonce, _transferSignature, _tokens, _txNonce.add(1));
  }

  function vote(uint _projectNonce, address _bidAddress, bytes memory _sig) public {
    require(projectMap[_projectNonce].deadline >= now, 'this project is end');

    bytes32 voteHash = voteHashBuild(_projectNonce, _bidAddress);
    bytes32 hash = ECRecovery.toEthSignedMessageHash(voteHash);
    address voter = ECRecovery.recover(hash, _sig);

    require(org.getUserRank(voter) == 9, 'user rank not correct');
    require(mht.balanceOf(voter) >= 5000, 'insufficient token');

    address prevChoice = voterChoiceMap[_projectNonce][voter];
    if (prevChoice != address(0)) {
      votesMap[_projectNonce][prevChoice] = votesMap[_projectNonce][prevChoice].sub(1);
    } else {
      projectMap[_projectNonce].voters = projectMap[_projectNonce].voters.add(1);
      voterRewardStatusMap[_projectNonce][voter] = 1;
    }
    votesMap[_projectNonce][_bidAddress] = votesMap[_projectNonce][_bidAddress].add(1);
    voterChoiceMap[_projectNonce][voter] = _bidAddress;
  }

  function delegatedVote(
    uint _fee,
    bytes memory _feeSignature,
    uint _txNonce,
    uint _projectNonce,
    address _bidAddress,
    bytes memory _voteSig
  ) public {
    require(mht.delegatedTransfer(_feeSignature, msg.sender, _fee, 0, _txNonce));
    vote(_projectNonce, _bidAddress, _voteSig);
  }

  function endProject (uint _projectNonce) public {
    require(projectMap[_projectNonce].deadline < now, 'this project is running');
    address[] memory bidAddrs = projectMap[_projectNonce].bids;
    address resultBidAddr;
    uint votes;
    for (uint index = 0; index < bidAddrs.length; index++) {
      uint bidVotes = votesMap[_projectNonce][bidAddrs[index]];
      if (votes < bidVotes) {
        votes = bidVotes;
        resultBidAddr = bidAddrs[index];
      }
    }
    projectResultMap[_projectNonce] = resultBidAddr;
  }

  function shareTokens(uint _projectNonce, address[] memory voters) public {
    address resultBidAddr = projectResultMap[_projectNonce];
    require(resultBidAddr != address(0), 'you should end this project before share tokens');

    Bid memory resultBid = bidMap[_projectNonce][resultBidAddr];
    uint perUserToken = resultBid.token.div(projectMap[_projectNonce].bids.length);

    for (uint index = 0; index < voters.length; index++) {
      if (voterRewardStatusMap[_projectNonce][voters[index]] == 1) {
        require(mht.transfer(voters[index], perUserToken));
      }
    }
  }

  function returnBidTokens(uint _projectNonce) public {
    address resultBidAddr = projectResultMap[_projectNonce];
    require(resultBidAddr != address(0), 'you should end this project before share tokens');
    require(msg.sender != resultBidAddr, 'you are the winning bidder');
    uint token = bidMap[_projectNonce][msg.sender].token;
    require(token > 0, 'bid is canceled or do not exists');
    require(mht.transfer(msg.sender, token));
    bidMap[_projectNonce][msg.sender].token = 0;
  }

  function voteHashBuild(
    uint _projectNonce,
    address _bidAddress
  ) public pure returns (bytes32) {
    return keccak256(abi.encodePacked('vote', _projectNonce, _bidAddress));
  }
}