/**
 *Submitted for verification at Etherscan.io on 2019-09-17
*/
pragma solidity ^0.4.24;

contract SafeMath {
  function safeMul(uint a, uint b) pure internal returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function safeSub(uint a, uint b) pure internal returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function safeAdd(uint a, uint b) pure internal returns (uint) {
    uint c = a + b;
    assert(c>=a && c>=b);
    return c;
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

contract ErrorReporter {

    /**
      * @dev `error` corresponds to enum Error; `info` corresponds to enum FailureInfo, and `detail` is an arbitrary
      * contract-specific code that enables us to report opaque error codes from upgradeable contracts.
      **/
    event Failure(string name, uint error);

    enum Error {
        NO_ERROR,
        INVALIDE_ADMIN,
        WITHDRAW_TOKEN_AMOUNT_ERROR,
        WITHDRAW_TOKEN_TRANSER_ERROR,
        TOKEN_INSUFFICIENT_ALLOWANCE,
        TOKEN_INSUFFICIENT_BALANCE,
        TRANSFER_FROM_ERROR,
        LENDER_INSUFFICIENT_BORROW_ALLOWANCE,
        LENDER_INSUFFICIENT_BORROWER_BALANCE,
        LENDER_TRANSFER_FROM_BORROW_ERROR,
        LENDER_INSUFFICIENT_ADMIN_ALLOWANCE,
        LENDER_INSUFFICIENT_ADMIN_BALANCE,
        LENDER_TRANSFER_FROM_ADMIN_ERROR,
        CALL_MARGIN_ALLOWANCE_ERROR,
        CALL_MARGIN_BALANCE_ERROR,
        CALL_MARGIN_TRANSFER_ERROR,
        REPAY_ALLOWANCE_ERROR,
        REPAY_BALANCE_ERROR,
        REPAY_TX_ERROR,
        FORCE_REPAY_ALLOWANCE_ERROR,
        FORCE_REPAY_BALANCE_ERROR,
        FORCE_REPAY_TX_ERROR,
        CLOSE_POSITION_ALLOWANCE_ERROR,
        CLOSE_POSITION_TX_ERROR,
        CLOSE_POSITION_MUST_ADMIN_BEFORE_DEADLINE,
        CLOSE_POSITION_MUST_ADMIN_OR_LENDER_AFTER_DEADLINE,
        LENDER_TEST_TRANSFER_ADMIN_ERROR,
        LENDER_TEST_TRANSFER_BORROWR_ERROR,
        LENDER_TEST_TRANSFERFROM_ADMIN_ERROR,
        LENDER_TEST_TRANSFERFROM_BORROWR_ERROR,
        SEND_TOKEN_AMOUNT_ERROR,
        SEND_TOKEN_TRANSER_ERROR,
        DEPOSIT_TOKEN,
        CANCEL_ORDER,
        REPAY_ERROR,
        FORCE_REPAY_ERROR,
        LENDER_SEND_ETH_ERROR,
        REPAY_SEND_ETH_ERROR,
        FORCE_REPAY_SEND_ETH_ERROR
    }

    /**
      * @dev use this when reporting a known error from the money market or a non-upgradeable collaborator
      */
    function fail(string name, Error err) internal returns (uint) {
        emit Failure(name, uint(err));

        return uint(err);
    }
}

library ERC20AsmFn {

    function isContract(address addr) internal {
        assembly {
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
    }

    function handleReturnData() internal returns (bool result) {
        assembly {
            switch returndatasize()
            case 0 { // not a std erc20
                result := 1
            }
            case 32 { // std erc20
                returndatacopy(0, 0, 32)
                result := mload(0)
            }
            default { // anything else, should revert for safety
                revert(0, 0)
            }
        }
    }

    function asmTransfer(address _erc20Addr, address _to, uint256 _value) internal returns (bool result) {

        // Must be a contract addr first!
        isContract(_erc20Addr);

        // call return false when something wrong
        require(_erc20Addr.call(bytes4(keccak256("transfer(address,uint256)")), _to, _value), "asmTransfer error");

        // handle returndata
        return handleReturnData();
    }

    function asmTransferFrom(address _erc20Addr, address _from, address _to, uint256 _value) internal returns (bool result) {

        // Must be a contract addr first!
        isContract(_erc20Addr);

        // call return false when something wrong
        require(_erc20Addr.call(bytes4(keccak256("transferFrom(address,address,uint256)")), _from, _to, _value), "asmTransferFrom error");

        // handle returndata
        return handleReturnData();
    }

}

contract TheForceLending is SafeMath, ErrorReporter {
  using ERC20AsmFn for EIP20Interface;

  enum OrderState {
    ORDER_STATUS_PENDING,
    ORDER_STATUS_ACCEPTED
  }

  struct Order_t {
    bytes32 partner_id;
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
  address public offcialFeeAccount; //the account that will receive fees
  bytes32 public offcialPartnerId; //the offical partnerId for fastborrow and fastlender
  uint public saveRate; // 1+interest rate per block for savings in fixed-point

   mapping (bytes32 => address) public partnerAccounts;// bytes32-> address, eg: platformA->0xa{40}, platfromB->0xb{40}
   mapping (bytes32 => mapping (address => mapping (address => uint))) public partnerTokens;// platform->tokenContract->address->balance
   mapping (bytes32 => mapping (address => mapping (bytes32 => Order_t))) public partnerOrderBook;// platform->address->hash->order_t
   mapping (bytes32 => mapping (address => mapping (address => uint))) prevUpdateBlock; // platform->tokenContract->address->Block number of last update block
   mapping (address => uint) public creditScore;//信用分，信用分高享受手续费优惠
   mapping (bytes32 => mapping (address => bytes32[])) partnerOrderHash;

  function numHash(bytes32 partnerId, address usr) public view returns (uint) {
      return partnerOrderHash[partnerId][usr].length;
  }

  function listHash(bytes32 partnerId, address usr) public view returns (bytes32[]) {
      return partnerOrderHash[partnerId][usr];
  }

  function deleteHashByIndex(bytes32 partnerId, address usr, uint index) internal {
     require(index < partnerOrderHash[partnerId][usr].length, "out of index");
     delete partnerOrderHash[partnerId][usr][index];
  }
  
  function deleteHash(bytes32 partnerId, address usr, bytes32 hash) internal {
      uint index = 0;
      for (uint i = 0; i < partnerOrderHash[partnerId][usr].length; i++) {
          if (partnerOrderHash[partnerId][usr][i] == hash) {
              index = i;
              break;
          }
      }
      //Delete With Shift
      if (partnerOrderHash[partnerId][usr].length >= 1) {
        for (uint j = index; j < partnerOrderHash[partnerId][usr].length - 1; j++) {
          partnerOrderHash[partnerId][usr][j] = partnerOrderHash[partnerId][usr][j + 1];
        }
        deleteHashByIndex(partnerId, usr, partnerOrderHash[partnerId][usr].length - 1);
        partnerOrderHash[partnerId][usr].length--;
      }
  }

  event Borrow(bytes32 partnerId,
                address tokenGet,
                  uint amountGet,
                  address tokenGive,
                  uint amountGive,
                  uint nonce,
                  uint lendingCycle,
                  uint pledgeRate,
                  uint interestRate,
                  uint feeRate,
                  address user,
                  bytes32 hash,
                  uint status);
  event Lend(bytes32 partnerId, bytes32 lenderPartnerId, address borrower, bytes32 txId, address token, uint amount, address give);//txId为借款单txId
  event CancelOrder(bytes32 partnerId, address borrower, bytes32 txId, address by);//取消借款单，只能被borrower或者合约取消
  event Callmargin(bytes32 partnerId, address borrower, bytes32 txId, address token, uint amount, address by);
  event Repay(bytes32 partnerId, address borrower, bytes32 txId, address token, uint amount, address by);
  event Closepstion(bytes32 partnerId, address borrower, bytes32 txId, address token, address by);
  event Forcerepay(bytes32 partnerId, address borrower, bytes32 txId, address token, address by);
  event Deposit(bytes32 partnerId, address token, address user, uint256 amount, uint256 balance);
  event SendEth(bytes32 partnerId, address token, address user, uint256 amount, uint256 balance);

  constructor(address admin_, address offcialFeeAccount_) public {
    admin = admin_;
    offcialFeeAccount = offcialFeeAccount_;
  }

  function() public payable {
    revert("fallback can't be payable");
 }

  modifier onlyAdmin() {
    require(msg.sender == admin, "only admin can do this!");
    _;
  }

  function changeAdmin(address admin_) public onlyAdmin {
    admin = admin_;
  }

  function changeFeeAccount(address offcialFeeAccount_) public onlyAdmin {
    offcialFeeAccount = offcialFeeAccount_;
  }

  function setSaveRate(uint rate) public onlyAdmin {
		saveRate = rate;
  }

  function setOffcialPartnerId(bytes32 id) public onlyAdmin {
    offcialPartnerId = id;
  }

  //增
  function addPartner(bytes32 partnerId, address partner) public onlyAdmin {
    require(partnerAccounts[partnerId] == address(0), "already exists!");
    partnerAccounts[partnerId] = partner;
  }

  //删
  function delPartner(bytes32 partnerId) public onlyAdmin {
    delete partnerAccounts[partnerId];
  }

  //改
  function modPartner(bytes32 partnerId, address partner) public onlyAdmin {
    require(partnerAccounts[partnerId] != address(0), "not exists!");
    partnerAccounts[partnerId] = partner;
  }

  //查
  function getPartner(bytes32 partnerId) public view returns (address) {
    return partnerAccounts[partnerId];
  }
  
  //充值ETH
  function deposit(bytes32 partnerId) public payable  {
    partnerTokens[partnerId][address(0)][msg.sender] = safeAdd(partnerTokens[partnerId][address(0)][msg.sender], msg.value);
    emit Deposit(partnerId, address(0), msg.sender, msg.value, partnerTokens[partnerId][address(0)][msg.sender]);
  }

  function sendEth(bytes32 partnerId, address dst, address token, uint256 amount) internal returns (bool success) {
    if (token != 0) revert("invalid token address!");
    if (partnerTokens[partnerId][token][msg.sender] < amount) revert("invalid amount");//lend时，dst没有eth，所以取消判断
    partnerTokens[partnerId][token][msg.sender] = safeSub(partnerTokens[partnerId][token][msg.sender], amount);
    dst.transfer(amount);

    emit SendEth(partnerId, token, dst, amount, partnerTokens[partnerId][token][msg.sender]);
    return true;
  }

  //计算单利, interestPerBlock, 5%->5e16
  function calcSimpleInterest(uint interestPerBlock, uint numBlocks) public view returns (uint interest) {
    return interestPerBlock * numBlocks;
  }

  //充值token，项目方首先调用，填充资金池，充入USDT和DAI,按块计算利息
  function depositSavings(bytes32 partnerId, address token, uint amount) public returns (uint) {
    //remember to call Token(address).approve(this, amount) or this contract will not be able to do the transfer on your behalf.
    require(partnerAccounts[partnerId] != address(0), "parnerId must add first");

    require(safeTransferFrom(token, msg.sender, this, this, amount) == 0, "safeTransferFrom error");
    partnerTokens[partnerId][token][msg.sender] = safeAdd(partnerTokens[partnerId][token][msg.sender], amount);

    prevUpdateBlock[partnerId][token][msg.sender] = block.number;
    return 0;
  }

  //提现存款和利息
  function withdrawSavings(bytes32 partnerId, address token, uint amount) public returns (uint) {
    require(partnerAccounts[partnerId] != address(0), "partnerId must add first");
    require(token != 0, "invalid token address");

    if (partnerTokens[partnerId][token][msg.sender] < amount) {
        return uint(Error.WITHDRAW_TOKEN_AMOUNT_ERROR);
    }
    partnerTokens[partnerId][token][msg.sender] = safeSub(partnerTokens[partnerId][token][msg.sender], amount);
    if (!EIP20Interface(token).asmTransfer(msg.sender, amount)) {
        return uint(Error.WITHDRAW_TOKEN_TRANSER_ERROR);
    }

    //FIXME: 添加利息检查，防止用户提取多余利息
    if (block.number >= prevUpdateBlock[partnerId][token][msg.sender]) {
      uint interestAmount = amount*calcSimpleInterest(saveRate, block.number - prevUpdateBlock[partnerId][token][msg.sender])/1e18;
      //发送利息给用户
      if (!EIP20Interface(token).asmTransfer(msg.sender, interestAmount)) {
          return uint(Error.WITHDRAW_TOKEN_TRANSER_ERROR);
      }
    }
    return 0;
  }

  function safeTransferFrom(address token, address owner, address spender, address to, uint amount) internal returns (uint) {
    require(amount > 0, "invalid safeTransferFrom amount");
    require(token != 0, "invalid token address!");

    if (owner != spender) {
      if (EIP20Interface(token).allowance(owner, spender) < amount) {
        return uint(Error.TOKEN_INSUFFICIENT_ALLOWANCE);
      }
    }
