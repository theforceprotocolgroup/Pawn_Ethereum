pragma solidity >=0.4.23;

contract SafeMath {
  function safeMul(uint a, uint b) internal returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function safeSub(uint a, uint b) internal returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function safeAdd(uint a, uint b) internal returns (uint) {
    uint c = a + b;
    assert(c>=a && c>=b);
    return c;
  }

  function assert(bool assertion) internal {
    if (!assertion) throw;
  }
}

contract EIP20Interface {
    /* This is a slight change to the ERC20 base standard.
    function totalSupply() constant returns (uint256 supply);
    is replaced with:
    uint256 public totalSupply;
    This automatically creates a getter function for the totalSupply.
    This is moved to the base contract since public getter functions are not
    currently recognised as an implementation of the matching abstract
    function by the compiler.
    */
    /// total amount of tokens
    uint256 public totalSupply;

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) public view returns (uint256 balance);

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) public returns (bool success);

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);

    /// @notice `msg.sender` approves `_spender` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of tokens to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address _spender, uint256 _value) public returns (bool success);

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) public view returns (uint256 remaining);

    // solhint-disable-next-line no-simple-event-func-name
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}

contract TheForceLending is SafeMath {
  enum OrderState {
    ORDER_STATUS_PENDING,
    ORDER_STATUS_ACCEPTED
  }

  struct Order_t {
    bytes32 tx_id;
    uint deadline;
    OrderState state;
    
    address borrower;
    address lender;

    uint lending_cycle;
    
    address token_get;
    uint amount_get;

    address token_pledge;//tokenGive
    uint amount_pledge;//amountGive

    uint _nonce;

    uint pledge_rate;
    uint interest_rate;
    uint fee_rate;
  }

  address public admin; //the admin address
  address public feeAccount; //the account that will receive fees
  mapping (address => mapping (address => uint)) public tokens; //mapping of token addresses to mapping of account balances (token=0 means Ether)
  mapping (address => mapping(bytes32 => Order_t)) public orderBook;// address->hash->order_t

  event Borrow(address tokenGet, 
                  uint amountGet, 
                  address tokenGive, 
                  uint amountGive,
                  uint nonce, 
                  uint lendingCycle,
                  uint pledgeRate,
                  uint interestRate,
                  uint feeRate,
                  address user);
  event Lend(address borrower, bytes32 txId, address token, uint amount, address give);//txId为借款单txId
  event CancelOrder(address borrower, bytes32 txId, address by);//取消借款单，只能被borrower或者合约取消
  event Callmargin(address borrower, bytes32 txId, address token, uint amount, address by);
  event Repay(address borrower, bytes32 txId, address token, uint amount, address by);
  event Closepstion(address borrower, bytes32 txId, address token, address by);
  event Forcerepay(address borrower, bytes32 txId, address token, address by);
  event Cancel(address borrower, address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s);
  event Deposit(address token, address user, uint amount, uint balance);
  event Withdraw(address token, address user, uint amount, uint balance);

  function TheForceLending(address admin_, address feeAccount_) public payable {
    admin = admin_;
    feeAccount = feeAccount_;
  }

  function() payable {
    throw;
 }

  function changeAdmin(address admin_) {
    if (msg.sender != admin) throw;
    admin = admin_;
  }


  function changeFeeAccount(address feeAccount_) {
    if (msg.sender != admin) throw;
    feeAccount = feeAccount_;
  }

  function deposit() payable {
    tokens[0][msg.sender] = safeAdd(tokens[0][msg.sender], msg.value);
    Deposit(0, msg.sender, msg.value, tokens[0][msg.sender]);
  }

  function withdraw(uint amount) {
    if (tokens[0][msg.sender] < amount) throw;
    tokens[0][msg.sender] = safeSub(tokens[0][msg.sender], amount);
    if (!msg.sender.call.value(amount)()) throw;
    Withdraw(0, msg.sender, amount, tokens[0][msg.sender]);
  }
  
  function depositToken(address token, uint amount) {
    //remember to call Token(address).approve(this, amount) or this contract will not be able to do the transfer on your behalf.
    if (token==0) throw;

    if (EIP20Interface(token).allowance(msg.sender, address(this)) < amount) {
        throw;
    }


    if (!EIP20Interface(token).transferFrom(msg.sender, address(this), amount)) {
        throw;
    }
    tokens[token][msg.sender] = safeAdd(tokens[token][msg.sender], amount);
    Deposit(token, msg.sender, amount, tokens[token][msg.sender]);
  }
  
  function withdrawToken(address token, uint amount) {
    if (token==0) throw;
    if (tokens[token][msg.sender] < amount) throw;
    tokens[token][msg.sender] = safeSub(tokens[token][msg.sender], amount);
    if (!EIP20Interface(token).transfer(msg.sender, amount)) throw;
    Withdraw(token, msg.sender, amount, tokens[token][msg.sender]);
  }

  function balanceOf(address token, address user) constant returns (uint) {
    return tokens[token][user];
  }

  function borrow(address tokenGet, //借出币种地址
                  uint amountGet, //借出币种数量
                  address tokenGive, //抵押币种地址
                  uint amountGive,//抵押币种数量
                  uint nonce, 
                  uint lendingCycle,
                  uint pledgeRate,
                  uint interestRate,
                  uint feeRate) {
    bytes32 hash = sha256(this, tokenGet, amountGet, tokenGive, amountGive, nonce, lendingCycle, pledgeRate, interestRate, feeRate);

    orderBook[msg.sender][hash] = Order_t({
      tx_id: hash,
      deadline: 0,
      state: OrderState.ORDER_STATUS_PENDING,
      borrower: msg.sender,
      lender: address(0),
      lending_cycle: lendingCycle,
      token_get: tokenGet,
      amount_get: amountGet,
      token_pledge: tokenGive,
      amount_pledge: amountGive,
      _nonce: nonce,
      pledge_rate: pledgeRate,
      interest_rate: interestRate, 
      fee_rate: feeRate
    });
    depositToken(tokenGive, amountGive);

    Borrow(tokenGet, amountGet, tokenGive, amountGive, nonce, lendingCycle, pledgeRate, interestRate, feeRate, msg.sender);
  }

  function lend(address borrower, bytes32 hash, address token, uint amount, uint feeAmount) {
    require(orderBook[borrower][hash].borrower != address(0));//order not found
    require(orderBook[borrower][hash].borrower != msg.sender);//cannot lend to self
    require(orderBook[borrower][hash].token_get == token);//attempt to use an invalid type of token
    require(orderBook[borrower][hash].amount_get == amount - feeAmount);//单个出借金额不足，后续可以考虑多个出借人，现在只考虑一个出借人

    orderBook[borrower][hash].deadline = now + orderBook[borrower][hash].lending_cycle * (1 days);
    orderBook[borrower][hash].lender = msg.sender;
    orderBook[borrower][hash].state = OrderState.ORDER_STATUS_ACCEPTED;
    
    if (EIP20Interface(token).allowance(msg.sender, orderBook[borrower][hash].borrower) < amount) {
        throw;
    }
    EIP20Interface(token).transferFrom(msg.sender, orderBook[borrower][hash].borrower, amount);
    
    if (EIP20Interface(token).allowance(msg.sender, feeAccount) < feeAmount) {
        throw;
    }
    EIP20Interface(token).transferFrom(msg.sender, feeAccount, feeAmount);


    Lend(borrower, hash, token, amount, msg.sender);
  }

  function cancelOrder(address borrower, bytes32 hash) {
    require(orderBook[borrower][hash].borrower != address(0));//order not found
    require(orderBook[borrower][hash].borrower == msg.sender || address(this) == msg.sender);//only borrower or contract can do this operation
    
    if (EIP20Interface(orderBook[borrower][hash].token_pledge).allowance(address(this), orderBook[borrower][hash].borrower) < orderBook[borrower][hash].amount_pledge) {
        throw;
    }
    
    address token = orderBook[borrower][hash].token_pledge;
    
    tokens[token][borrower] = safeSub(tokens[token][borrower], orderBook[borrower][hash].amount_pledge);
    
    EIP20Interface(orderBook[borrower][hash].token_pledge).transferFrom(address(this), orderBook[borrower][hash].borrower, orderBook[borrower][hash].amount_pledge);

    delete orderBook[borrower][hash];

    CancelOrder(borrower, hash, msg.sender);
  }

  function callmargin(address borrower, bytes32 hash, address token, uint amount) {
    require(orderBook[borrower][hash].borrower != address(0));
    require(amount > 0);
    require(token != address(0));
    require(orderBook[borrower][hash].state == OrderState.ORDER_STATUS_PENDING);
    require(orderBook[borrower][hash].token_pledge == token);
    
    if (EIP20Interface(token).allowance(msg.sender, address(this)) < amount) {
        throw;
    }

    orderBook[borrower][hash].amount_pledge += amount;
    tokens[token][borrower] = safeAdd(tokens[token][borrower], amount);

    EIP20Interface(token).transferFrom(msg.sender, address(this), amount);

    Callmargin(borrower, hash, token, amount, msg.sender);
  }

  function repay(address borrower, bytes32 hash, address token, uint amount) {
    require(orderBook[borrower][hash].borrower != address(0));
    require(orderBook[borrower][hash].state == OrderState.ORDER_STATUS_PENDING);
    require(token != address(0));
    require(token == orderBook[borrower][hash].token_get);
    require(amount > orderBook[borrower][hash].amount_get);
    
    if (EIP20Interface(token).allowance(msg.sender, orderBook[borrower][hash].lender) < orderBook[borrower][hash].amount_get) {
        throw;
    }
    
    if (EIP20Interface(orderBook[borrower][hash].token_pledge).allowance(address(this), orderBook[borrower][hash].borrower) < orderBook[borrower][hash].amount_pledge) {
        throw;
    }
    
    tokens[token][borrower] = safeSub(tokens[token][borrower], orderBook[borrower][hash].amount_get);
    EIP20Interface(token).transferFrom(msg.sender, orderBook[borrower][hash].lender, amount);
    
    EIP20Interface(orderBook[borrower][hash].token_pledge).transferFrom(address(this), orderBook[borrower][hash].borrower, orderBook[borrower][hash].amount_pledge);

    delete orderBook[borrower][hash];

    Repay(borrower, hash, token, amount, msg.sender);
  }

  function forcerepay(address borrower, bytes32 hash, address token) {
    require(orderBook[borrower][hash].borrower != address(0));
    require(token != address(0));
    require(token == orderBook[borrower][hash].token_pledge);
    
    if (EIP20Interface(token).allowance(address(this), orderBook[borrower][hash].lender) < orderBook[borrower][hash].amount_pledge) {
        throw;
    }

    tokens[token][borrower] = safeSub(tokens[token][borrower], orderBook[borrower][hash].amount_pledge);
    EIP20Interface(token).transferFrom(address(this), orderBook[borrower][hash].lender, orderBook[borrower][hash].amount_pledge);//合约发送抵押资产到出借人

    delete orderBook[borrower][hash];

    Forcerepay(borrower, hash, token, address(this));
  }

  function closepstion(address borrower, bytes32 hash, address token) {
    require(orderBook[borrower][hash].borrower != address(0));
    require(token != address(0));
    require(token == orderBook[borrower][hash].token_pledge);
    
    if (EIP20Interface(token).allowance(address(this), orderBook[borrower][hash].lender) < orderBook[borrower][hash].amount_pledge) {
        throw;
    }

    tokens[token][borrower] = safeSub(tokens[token][borrower], orderBook[borrower][hash].amount_pledge);
    EIP20Interface(token).transferFrom(address(this), orderBook[borrower][hash].lender, orderBook[borrower][hash].amount_pledge);//合约发送抵押资产到出借人

    delete orderBook[borrower][hash];

    Closepstion(borrower, hash, token, address(this));
  }

    // ADDITIONAL HELPERS ADDED FOR TESTING
    function hash(
        address tokenGet,
        uint amountGet,
        address tokenGive,
        uint amountGive,
        uint nonce,
        uint lendingCycle,
        uint pledgeRate,
        uint interestRate,
        uint feeRate
    )
        public
        view
        returns (bytes32) 
    {
        return sha256(this, tokenGet, amountGet, tokenGive, amountGive, nonce, lendingCycle, pledgeRate, interestRate, feeRate);
    }

    function isValidSignature(
        bytes32 _hash,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address signer
    )
        public
        view
        returns (bool) 
    {
        return signer == ecrecover(
            sha3("\x19Ethereum Signed Message:\n32", _hash),
            v,
            r,
            s
        );
    }
}
interface tokenRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) public; }

contract TokenERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping (address => uint256) public balanceOf;  // 
    mapping (address => mapping (address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Burn(address indexed from, uint256 value);


    function TokenERC20(uint256 initialSupply, string tokenName, string tokenSymbol) public {
        totalSupply = initialSupply * 10 ** uint256(decimals);
        balanceOf[msg.sender] = totalSupply;
        name = tokenName;
        symbol = tokenSymbol;
    }


    function _transfer(address _from, address _to, uint _value) internal {
        require(_to != 0x0);
        require(balanceOf[_from] >= _value);
        require(balanceOf[_to] + _value > balanceOf[_to]);
        uint previousBalances = balanceOf[_from] + balanceOf[_to];
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        Transfer(_from, _to, _value);
        assert(balanceOf[_from] + balanceOf[_to] == previousBalances);
    }

    function transfer(address _to, uint256 _value) public {
        _transfer(msg.sender, _to, _value);
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(_value <= allowance[_from][msg.sender]);     // Check allowance
        allowance[_from][msg.sender] -= _value;
        _transfer(_from, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) public
        returns (bool success) {
        allowance[msg.sender][_spender] = _value;
        return true;
    }

    function approveAndCall(address _spender, uint256 _value, bytes _extraData) public returns (bool success) {
        tokenRecipient spender = tokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, this, _extraData);
            return true;
        }
    }
}

contract WETH {
    string public name     = "Wrapped Ether";
    string public symbol   = "WETH";
    uint8  public decimals = 18;

    event  Approval(address indexed src, address indexed guy, uint wad);
    event  Transfer(address indexed src, address indexed dst, uint wad);
    event  Deposit(address indexed dst, uint wad);
    event  Withdrawal(address indexed src, uint wad);

    mapping (address => uint)                       public  balanceOf;
    mapping (address => mapping (address => uint))  public  allowance;

    function() external payable {
        deposit();
    }
    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
    function withdraw(uint wad) public {
        require(balanceOf[msg.sender] >= wad);
        balanceOf[msg.sender] -= wad;
        msg.sender.transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint) {
        return address(this).balance;
    }

    function approve(address guy, uint wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public
        returns (bool)
    {
        require(balanceOf[src] >= wad);

        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);

        return true;
    }
}
