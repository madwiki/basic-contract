pragma solidity >=0.4.25 <0.6.0;
import "./zeppelin-solidity/ECRecovery.sol";
import "./zeppelin-solidity/SafeMath.sol";

// ----------------------------------------------------------------------------
// 'FIXED' 'Example Fixed Supply Token' token contract
//
// Symbol    : FIXED
// Name    : Example Fixed Supply Token
// Total supply: 1,000,000,000.000000000000000000
// Decimals  : 18
//
// Enjoy.
//
// (c) BokkyPooBah / Bok Consulting Pty Ltd 2018. The MIT Licence.
// ----------------------------------------------------------------------------



// ----------------------------------------------------------------------------
// ERC Token Standard #20 Interface
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md
// ----------------------------------------------------------------------------
contract ERC20Interface {
  function totalSupply() public view returns (uint);
  function balanceOf(address tokenOwner) public view returns (uint balance);
  function allowance(address tokenOwner, address spender) public view returns (uint remaining);
  function transfer(address to, uint tokens) public returns (bool success);
  function approve(address spender, uint tokens) public returns (bool success);
  function transferFrom(address from, address to, uint tokens) public returns (bool success);

  event Transfer(address indexed from, address indexed to, uint tokens);
  event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}


// ----------------------------------------------------------------------------
// Contract function to receive approval and execute function in one call
//
// Borrowed from MiniMeToken
// ----------------------------------------------------------------------------
contract ApproveAndCallFallBack {
  function receiveApproval(address from, uint256 tokens, address token, bytes memory data) public;
}


// ----------------------------------------------------------------------------
// Owned contract
// ----------------------------------------------------------------------------
contract Owned {
  address public owner;
  address public newOwner;

  event OwnershipTransferred(address indexed _from, address indexed _to);

  constructor() public {
    owner = msg.sender;
  }

  modifier onlyOwner {
    require(msg.sender == owner);
    _;
  }

  function transferOwnership(address _newOwner) public onlyOwner {
    newOwner = _newOwner;
  }
  function acceptOwnership() public {
    require(msg.sender == newOwner);
    emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
    newOwner = address(0);
  }
}


// ----------------------------------------------------------------------------
// ERC20 Token, with the addition of symbol, name and decimals and a
// fixed supply
// ----------------------------------------------------------------------------
contract M_ManToken is ERC20Interface, Owned {
  using SafeMath for uint;

  address public rewardAddr;
  string public symbol;
  string public  name;
  uint8 public decimals;
  uint _baseUint;
  uint _totalSupply;

  mapping(address => uint) balances;
  mapping(address => mapping(address => uint)) allowed;
  mapping(address => uint) delegatedNonce;

  // ------------------------------------------------------------------------
  // Constructor
  // ------------------------------------------------------------------------
  constructor(address _team, address _marketing, address _investor) public {
    symbol = "MMT";
    name = "M-Man Token";
    decimals = 18;
    _baseUint= 10000000 * 10 ** uint(decimals);
    _totalSupply = 150 * _baseUint;
    uint teamToken = 35 * _baseUint;
    uint marketingToken = 15 * _baseUint;
    uint investorToken = 30 * _baseUint;
    balances[_team] = teamToken;
    balances[_marketing] = marketingToken;
    balances[_investor] = investorToken;
    emit Transfer(address(0), _team, teamToken);
    emit Transfer(address(0), _marketing, marketingToken);
    emit Transfer(address(0), _investor, investorToken);
  }

  function setReward(address _reward) public onlyOwner {
    require(rewardAddr == address(0), 'reward already set');
    uint rewardToken = 70 * _baseUint;
    balances[_reward] = rewardToken;
    rewardAddr = _reward;
    emit Transfer(address(0), owner, rewardToken);
  }

  // ------------------------------------------------------------------------
  // Total supply
  // ------------------------------------------------------------------------
  function totalSupply() public view returns (uint) {
    return _totalSupply.sub(balances[address(0)]);
  }


  // ------------------------------------------------------------------------
  // Get the token balance for account `tokenOwner`
  // ------------------------------------------------------------------------
  function balanceOf(address tokenOwner) public view returns (uint balance) {
    return balances[tokenOwner];
  }


  // ------------------------------------------------------------------------
  // Transfer the balance from token owner's account to `to` account
  // - Owner's account must have sufficient balance to transfer
  // - 0 value transfers are allowed
  // ------------------------------------------------------------------------
  function transfer(address to, uint tokens) public returns (bool success) {
    balances[msg.sender] = balances[msg.sender].sub(tokens);
    balances[to] = balances[to].add(tokens);
    emit Transfer(msg.sender, to, tokens);
    return true;
  }

  // ------------------------------------------------------------------------
  // Token owner can approve for `spender` to transferFrom(...) `tokens`
  // from the token owner's account
  //
  // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md
  // recommends that there are no checks for the approval double-spend attack
  // as this should be implemented in user interfaces 
  // ------------------------------------------------------------------------
  function approve(address spender, uint tokens) public returns (bool success) {
    allowed[msg.sender][spender] = tokens;
    emit Approval(msg.sender, spender, tokens);
    return true;
  }


  // ------------------------------------------------------------------------
  // Transfer `tokens` from the `from` account to the `to` account
  // 
  // The calling account must already have sufficient tokens approve(...)-d
  // for spending from the `from` account and
  // - From account must have sufficient balance to transfer
  // - Spender must have sufficient allowance to transfer
  // - 0 value transfers are allowed
  // ------------------------------------------------------------------------
  function transferFrom(address from, address to, uint tokens) public returns (bool success) {
    balances[from] = balances[from].sub(tokens);
    allowed[from][msg.sender] = allowed[from][msg.sender].sub(tokens);
    balances[to] = balances[to].add(tokens);
    emit Transfer(from, to, tokens);
    return true;
  }

  function delegatedTransfer(bytes memory _signature, address _to, uint _tokens, uint _fee, uint _nonce) public returns (bool success) {
    require(_to != address(0), 'address can not be 0x00');
    require(_tokens > 0, 'tokens can not be 0');

    bytes32 delegatedTxHash = delegatedTxHashBuild(_to, _tokens, _fee, _nonce);
    bytes32 hash = ECRecovery.toEthSignedMessageHash(delegatedTxHash);
    
    address from = ECRecovery.recover(hash, _signature);
    require(_nonce == delegatedNonce[from], 'invalid nonce');

    delegatedNonce[from] = delegatedNonce[from].add(1);
    balances[from] = balances[from].sub(_tokens).sub(_fee);
    balances[_to] = balances[_to].add(_tokens);
    balances[msg.sender] = balances[msg.sender].add(_fee);
    emit Transfer(from, _to, _tokens);
    return true;
  }

  function delegatedTxHashBuild(address _to, uint _tokens, uint _fee, uint _nonce) public pure returns (bytes32) {
    return keccak256(abi.encodePacked('delegatedTx', _to, _tokens, _fee, _nonce));
  }

  function tokenIssue(address _target) public returns (bool success) {
    require(msg.sender == rewardAddr, 'wrong msg.sender');
    balances[_target] = balances[_target].add(15000000000000000000);
    _totalSupply = _totalSupply.add(15000000000000000000);
    return true;
  }

  // ------------------------------------------------------------------------
  // Returns the amount of tokens approved by the owner that can be
  // transferred to the spender's account
  // ------------------------------------------------------------------------
  function allowance(address tokenOwner, address spender) public view returns (uint remaining) {
    return allowed[tokenOwner][spender];
  }


  // ------------------------------------------------------------------------
  // Token owner can approve for `spender` to transferFrom(...) `tokens`
  // from the token owner's account. The `spender` contract function
  // `receiveApproval(...)` is then executed
  // ------------------------------------------------------------------------
  function approveAndCall(address spender, uint tokens, bytes memory data) public returns (bool success) {
    allowed[msg.sender][spender] = tokens;
    emit Approval(msg.sender, spender, tokens);
    ApproveAndCallFallBack(spender).receiveApproval(msg.sender, tokens, address(this), data);
    return true;
  }


  // ------------------------------------------------------------------------
  // Don't accept ETH
  // ------------------------------------------------------------------------
  function () external payable {
    revert();
  }


  // ------------------------------------------------------------------------
  // Owner can transfer out any accidentally sent ERC20 tokens
  // ------------------------------------------------------------------------
  function transferAnyERC20Token(address tokenAddress, uint tokens) public onlyOwner returns (bool success) {
    return ERC20Interface(tokenAddress).transfer(owner, tokens);
  }
}