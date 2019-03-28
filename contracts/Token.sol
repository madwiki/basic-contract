pragma solidity >=0.4.25 <0.6.0;

contract Token {
    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) public view returns (uint balance) {}

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint _value) public returns (bool success) {}

    function delegatedTransfer(bytes memory _signature, address _to, uint _tokens, uint _fee, uint _nonce) public returns (bool success) {}

    function tokenIssue(address _target) public returns (bool success) {}

    event Transfer(address indexed _from, address indexed _to, uint _value);
    event Approval(address indexed _owner, address indexed _spender, uint _value);
}
