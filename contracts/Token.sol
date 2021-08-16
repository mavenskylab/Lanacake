pragma solidity ^0.8.4;

contract LanaToken {
    mapping(address => uint) public balances;
    mapping(address => mapping(address => uint)) public allowance;
    uint public totalSupply = 10000 * 10 ** 18;
    string public name = "Bambo";
    string public symbol = "BAMB";
    uint public decimals = 18;
    
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed from, address indexed to, uint value);
    
    constructor() {
         balances[msg.sender] = totalSupply;
    }
    
    function balanceOf(address owner) public view returns(uint) {
        return balances[owner];
    }
    
    function transfer(address to, uint value) public returns(bool) {
        require(balanceOf(msg.sender) >= value, 'insufficient balance');
        // Gas savings
        unchecked {
            balances[to] += value;
            balances[msg.sender] -= value;
        }
        emit Transfer(msg.sender, to, value);
        return true;
    }
    
    function transferFrom(address from, address to, uint value) public returns(bool) {
        require(balanceOf(from) >= value, 'insufficient balance');
        require(allowance[from][msg.sender] >= value, 'insufficient allowance');
        // Gas savings
        unchecked {
            balances[to] += value;
            balances[from] -= value;
        }
        emit Transfer(from, to, value);
        return true;
    }
    
    function approve(address spender, uint value) public returns(bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
}
