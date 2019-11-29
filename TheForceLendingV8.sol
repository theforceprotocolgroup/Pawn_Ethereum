/*
 * Copyright (c) The Force Protocol Development Team
 * Submitted for verification at Etherscan.io on 2019-09-17
*/

pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;


import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

library address_make_payable {
  function make_payable(address x) internal pure returns (address payable) {
    return address(uint160(x));
  }
}

contract TheForceLending {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using address_make_payable for address;

    enum OrderState {
        ORDER_STATUS_PENDING,
        ORDER_STATUS_ACCEPTED
    }

    struct TokenInfo {
        address token;
        uint256 amount;
    }

    struct RateInfo {
        uint256 _nonce;
        //lending_cycle(31-24Bytes) | pledge_rate(23-16Bytes) | interest_rate(15-8Bytes) | fee_rate(7-0Bytes)
        uint256 pack_data;
    }

    struct Order_t {
        bytes32 partner_id;
        uint256 deadline;
        OrderState state;

        address borrower;
        address lender;

        TokenInfo tokenInfoGet;
        TokenInfo tokenInfoGive;

        RateInfo rateInfo;

    }

    address public admin; //the admin address
    address public proposedAdmin;//use pull over push pattern for admin

    address public offcialFeeAccount; //the account that will receive fees
    address public proposedOfficialFeeAccount;//use pull over push pattern for offcialFeeAccount

    bytes32 public offcialPartnerId; //the offical partnerId for fastborrow and fastlender
    uint256 public saveRate; // 1+interest rate per block for savings in fixed-point

    // bytes32-> address, eg: platformA->0xa{40}, platfromB->0xb{40}
    mapping (bytes32 => address) public partnerAccounts;
    // platform->tokenContract->address->balance
    mapping (bytes32 => mapping (address => mapping (address => uint256))) public partnerTokens;
    // platform->address->hash->order_t
    mapping (bytes32 => mapping (address => mapping (bytes32 => Order_t))) public partnerOrderBook;
    // platform->tokenContract->address->Block number of last update block
    mapping (bytes32 => mapping (address => mapping (address => uint256))) public partnerLastUpdateBlock;
    //Credit score, high credit score, enjoy the fee discount（信用分，信用分高享受手续费优惠）
    mapping (address => uint256) public creditScore;
    mapping (bytes32 => mapping (address => bytes32[])) public partnerOrderHash;

    struct MapKey {
      bytes32 k1;
      address k2;
      bytes32 k3;
    }

    uint256 constant interestRateDenomitor = 1e18;

    function numHash(bytes32 partnerId, address usr) external view returns (uint256) {
        return partnerOrderHash[partnerId][usr].length;
    }

    function listHash(bytes32 partnerId, address usr) external view returns (bytes32[] memory) {
        return partnerOrderHash[partnerId][usr];
    }

    function deleteHashByIndex(bytes32 partnerId, address usr, uint256 index) internal {
        uint256 orderSize = partnerOrderHash[partnerId][usr].length;
        require(index < orderSize, "out of index");
        if (index < orderSize - 1) {
            partnerOrderHash[partnerId][usr][index] = partnerOrderHash[partnerId][usr][orderSize - 1];
        }
        delete partnerOrderHash[partnerId][usr][orderSize - 1];
    }

    function deleteHash(bytes32 partnerId, address usr, bytes32 hash) internal {
        uint256 index = 0;
        for (uint256 i = 0; i < partnerOrderHash[partnerId][usr].length; i++) {
            if (partnerOrderHash[partnerId][usr][i] == hash) {
                index = i;
                break;
            }
        }
        deleteHashByIndex(partnerId, usr, index);
    }

    event Borrow(bytes32 partnerId,
                address tokenGet,
                    uint256 amountGet,
                    address tokenGive,
                    uint256 amountGive,
                    uint256 nonce,
                    uint256 packData,
                    address user,
                    bytes32 hash,
                    uint256 status);

//txId is the loan order txId（txId为借款单txId）
event Lend(bytes32 partnerId, bytes32 lenderPartnerId, address borrower,
bytes32 txId, address token, uint256 amount, address give);
//Cancellation of the loan order can only be cancelled by the borrower or contract（取消借款单，只能被borrower或者合约取消）

event CancelOrder(bytes32 partnerId, address borrower, bytes32 txId, address by);

event Callmargin(bytes32 partnerId, address borrower, bytes32 txId, address token, uint256 amount, address by);

event Repay(bytes32 partnerId, address borrower, bytes32 txId, address token, uint256 amount, address by);

event Closepostion(bytes32 partnerId, address borrower, bytes32 txId, address token, address by);

event Forcerepay(bytes32 partnerId, address borrower, bytes32 txId, address token, address by);

event FastRepay(bytes32 partnerId, address borrower, bytes32 txId, address token, uint256 amount, address by);

event FastClosepostion(bytes32 partnerId, address borrower, bytes32 txId, address token, address by);

event FastForcerepay(bytes32 partnerId, address borrower, bytes32 txId, address token, address by);

event Deposit(bytes32 partnerId, address token, address user, uint256 amount, uint256 balance);

event SendEth(bytes32 partnerId, address token, address user, uint256 amount, uint256 balance);

event DepositSavings(bytes32 partnerId, address token, uint256 amount);
event WithdrawSavings(bytes32 partnerId, address token, uint256 amount);

constructor(address admin_, address offcialFeeAccount_) public {
  admin = admin_;
  offcialFeeAccount = offcialFeeAccount_;
}

function() external payable {
  revert("fallback can't be payable");
}

modifier onlyAdmin() {
  require(msg.sender == admin, "only admin can do this!");
  _;
}

modifier notNull(bytes32 partnerId) {
  require(partnerAccounts[partnerId] != address(0), "parnerId must be added first");
  _;
}

function proposeNewAdmin(address admin_) public onlyAdmin {
    proposedAdmin = admin_;
}

function claimAdministration() public {
    require(msg.sender == proposedAdmin, "Not proposed admin.");
    admin = proposedAdmin;
    proposedAdmin = address(0);
}

function proposeNewOffcialFeeAccount(address offcialFeeAccount_) public onlyAdmin {
    proposedOfficialFeeAccount = offcialFeeAccount_;
}

function claimOffcialFeeAccount() public {
    require(msg.sender == proposedOfficialFeeAccount, "Not proposed officialfee account.");
    offcialFeeAccount = proposedOfficialFeeAccount;
    proposedOfficialFeeAccount = address(0);
}

// Info: this function will not used in later, we will use dynamic calculation for borrow and lender rate.
// we will use our interest model instead of a sigmoid function.
function setSaveRate(uint256 rate) public onlyAdmin {
  saveRate = rate;
}

function setOffcialPartnerId(bytes32 id) public onlyAdmin {
  offcialPartnerId = id;
}

//add（增）
function addPartner(bytes32 partnerId, address partner) public onlyAdmin {
  require(partnerAccounts[partnerId] == address(0), "already exists!");
  partnerAccounts[partnerId] = partner;
}

//Delete（删）
function delPartner(bytes32 partnerId) public onlyAdmin {
  delete partnerAccounts[partnerId];
}

//Modify（改）
function modPartner(bytes32 partnerId, address partner) public onlyAdmin {
  require(partnerAccounts[partnerId] != address(0), "not exists!");
  partnerAccounts[partnerId] = partner;
}

//Check（查）
function getPartner(bytes32 partnerId) public view returns (address) {
  return partnerAccounts[partnerId];
}

//Deposit ETH(充值ETH)
function deposit(bytes32 partnerId) public payable  {
  partnerTokens[partnerId][address(0)][msg.sender] = partnerTokens[partnerId][address(0)][msg.sender].add(msg.value);
  emit Deposit(partnerId, address(0), msg.sender, msg.value, partnerTokens[partnerId][address(0)][msg.sender]);
}

function sendEth(bytes32 partnerId, address payable dst, uint256 amount) internal returns (bool success) {
  //When lend, dst has no eth, so cancel the judgment.（lend时，dst没有eth，所以取消判断）
  partnerTokens[partnerId][address(0)][msg.sender] = partnerTokens[partnerId][address(0)][msg.sender].sub(amount);
  dst.transfer(amount);

  emit SendEth(partnerId, address(0), dst, amount, partnerTokens[partnerId][address(0)][msg.sender]);
  return true;
}

//Calculate interest of each block（计算单利）, interestPerBlock, 5%->5e16
function calcSimpleInterest(uint256 interestPerBlock, uint256 numBlocks) public pure returns (uint256 interest) {
  return interestPerBlock.mul(numBlocks);
}

/*
Deposit token, smart contract owner calls firstly, fills the pool of funds,
Deposit USDT and DAI, calculates interest by block.
充值token，合约所有者首先调用，填充资金池，充入USDT和DAI,按块计算利息*/
function depositSavings(bytes32 partnerId, address token, uint256 amount) public notNull(partnerId) returns (uint256) {
  /*
  Remember to call Token(address).approve(this, amount) or contract will not be able to do the transfer on your behalf.
  */

  require(safeTransferFrom(token, msg.sender, address(this), address(this), amount) == 0, "safeTransferFrom error");
  partnerTokens[partnerId][token][msg.sender] = partnerTokens[partnerId][token][msg.sender].add(amount);

  partnerLastUpdateBlock[partnerId][token][msg.sender] = block.number;

  emit DepositSavings(partnerId, token, amount);

  return 0;
}

function _withdrawAsset(bytes32 partnerId, address token, address to, uint256 amount, bool transferInterest) internal notNull(partnerId) returns (uint256) {
  require(token != address(0) && to != address(0) && amount != 0, "invalid token address or amount");

  partnerTokens[partnerId][token][to] = partnerTokens[partnerId][token][to].sub(amount);
  IERC20(token).safeTransfer(to, amount);

  //FIXME: Add interest check to prevent users from withdrawing excess interest（添加利息检查，防止用户提取多余利息）
  if (transferInterest) {
    uint256 delta = block.number.sub(partnerLastUpdateBlock[partnerId][token][to]);
    uint256 interestAmount = amount.mul(calcSimpleInterest(saveRate, delta)).div(interestRateDenomitor);
    //Send interest to the user（发送利息给用户）
    IERC20(token).safeTransfer(to, interestAmount);
  }

  return 0;
}

//Withdrawal of deposits and interest（提现存款和利息）
function withdrawSavings(bytes32 partnerId, address token, uint256 amount) public returns (uint256) {
  _withdrawAsset(partnerId, token, msg.sender, amount, true);
  emit WithdrawSavings(partnerId, token, amount);

  return 0;
}

function safeTransferFrom(address token, address owner, address spender, address to, uint256 amount) internal returns (uint256) {
  require(amount > 0, "invalid safeTransferFrom amount");
  require(token != address(0), "invalid token address!");

  if (owner != spender) {
      require(IERC20(token).allowance(owner, spender) >= amount, "Insufficient allowance");
  }

  require(IERC20(token).balanceOf(owner) >= amount, "Insufficient balance");

  if (owner != spender) {
      IERC20(token).safeTransferFrom(owner, to, amount);
  } else {
      IERC20(token).safeTransfer(to, amount);
  }

  return 0;
}

function depositToken(bytes32 partnerId, address token, uint256 amount) public notNull(partnerId) returns (uint256){
  //remember to call Token(address).approve(this, amount) or this contract will not be able to do the transfer on your behalf.
  safeTransferFrom(token, msg.sender, address(this), address(this), amount);
  partnerTokens[partnerId][token][msg.sender] = partnerTokens[partnerId][token][msg.sender].add(amount);

  return 0;
}

function withdrawToken(bytes32 partnerId, address token, uint256 amount) internal returns (uint256) {
  return _withdrawAsset(partnerId, token, msg.sender, amount, false);
}

function sendToken(bytes32 partnerId, address token, address to, uint256 amount) internal returns (uint256) {
  _withdrawAsset(partnerId, token, to, amount, false);
  return 0;
}

function balanceOf(bytes32 partnerId, address token, address user) public view returns (uint256) {
  return partnerTokens[partnerId][token][user];
}

function borrow(bytes32 partnerId,//Partner platform mark（平台标记）
                TokenInfo memory tokenInfoGet,//Lending token information（借出币种信息）
                TokenInfo memory tokenInfoGive,//Pawn token information（抵押币种信息）
                RateInfo memory rateInfo,
                bool isC2C)  public notNull(partnerId) payable returns (uint256) {
  bytes32 txid = hash(partnerId, tokenInfoGet.token, tokenInfoGet.amount, tokenInfoGive.token, tokenInfoGive.amount, rateInfo._nonce, rateInfo.pack_data);
  require(partnerOrderBook[partnerId][msg.sender][txid].borrower == address(0), "order already exists");

  //集中借贷
  if (!isC2C) {
    require(IERC20(tokenInfoGet.token).balanceOf(address(this)) >= tokenInfoGet.amount, "insuffcient balance");
  }

  uint status = 0;

  partnerOrderBook[partnerId][msg.sender][txid] = Order_t({
    partner_id: partnerId,
    deadline: 0,
    state: OrderState.ORDER_STATUS_PENDING,
    borrower: msg.sender,
    lender: address(0),
    tokenInfoGet: tokenInfoGet,
    tokenInfoGive: tokenInfoGive,
    rateInfo: rateInfo
  });

  partnerOrderHash[partnerId][msg.sender].push(txid);

  if (tokenInfoGive.token != address(0)) {
      require(msg.value == 0, "msg.value must be zero");
    status = depositToken(partnerId, tokenInfoGive.token, tokenInfoGive.amount);
  } else {
    //deposit eth
    require(tokenInfoGive.amount == msg.value, "amount must equal to msg.value");
    deposit(partnerId);
  }
  require(status == 0, "borrow: deposit token error!");

  //集中借贷
  if (!isC2C) {
    /*
      合约可以出借,出借人是合约，必须加this，表示msg.sender是合约地址
      The contract can be used as a lender. If the lender is a contract, "this" must be added to indicate that msg.sender is the contract address.
    */
    uint256[3] memory x;
    x[0] = tokenInfoGet.amount;
    x[1] = x[2] = 0;
    MapKey memory mapKey;
    mapKey.k1 = partnerId;
    mapKey.k2 = msg.sender;
    mapKey.k3 = txid;
    this.fastLend(mapKey, offcialPartnerId, tokenInfoGet.token, x);
  }

  emit Borrow(partnerId, tokenInfoGet.token, tokenInfoGet.amount, tokenInfoGive.token, tokenInfoGive.amount, rateInfo._nonce, rateInfo.pack_data, msg.sender, txid, status);
  return 0;
}

function c2cBorrow(bytes32 partnerId,//Partner platform mark（平台标记）
                    TokenInfo memory tokenInfoGet,
                    TokenInfo memory tokenInfoGive,
                    RateInfo memory rateInfo
                ) public payable returns (uint256){
  return borrow(partnerId, tokenInfoGet, tokenInfoGive, rateInfo, true);
}

//Borrowing form fund pool rapidly（从资金池快速借款）
  function fastBorrow(bytes32 partnerId,//Partner platform mark（平台标记）
                TokenInfo memory tokenInfoGet,
                TokenInfo memory tokenInfoGive,
                RateInfo memory rateInfo
                ) public payable returns (uint256){
  return borrow(partnerId, tokenInfoGet, tokenInfoGive, rateInfo, false);
}

function fastLend(MapKey memory mapKey, bytes32 lenderPartnerId, address token, uint256[3] memory amountArray) public returns (uint) {
  return lend(mapKey, lenderPartnerId, token, amountArray, false);
}

/*
A borrowing, B lending, A's arrival amount is the number of applications, B's lending quantity includes: A's application quantity + handling fee (smart contract handling fee + platform partner fee, handling fee may be 0)
（A借款，B出借，A的到账数量为申请数量，B出借的数量包括：A的申请数量+手续费（智能合约手续费+平台合作方手续费，手续费可能为0））
*/
function lend(MapKey memory mapKey, bytes32 lenderPartnerId, address token, uint256[3] memory amountArray, bool isC2C) public notNull(mapKey.k1) payable returns (uint256) {
  bytes32 partnerId = mapKey.k1;
  address borrower = mapKey.k2;
  bytes32 hash = mapKey.k3;

  if (isC2C) {
   require(partnerAccounts[lenderPartnerId] != address(0), "lenderPartnerId must be added first");
  }

  require(partnerOrderBook[partnerId][borrower][hash].borrower != address(0), "order not found");
  require(partnerOrderBook[partnerId][borrower][hash].borrower != msg.sender, "cannot lend to self");
  require(partnerOrderBook[partnerId][borrower][hash].tokenInfoGet.token == token, "attempt to use an invalid type of token");
  if (isC2C) {
    //Insufficient single lending amount, we will consider introducing multiple lenders in the future, and now only consider one lender（单个出借金额不足，后续可以考虑多个出借人，现在只考虑一个出借人）
    require(partnerOrderBook[partnerId][borrower][hash].tokenInfoGet.amount == amountArray[0].sub(amountArray[1]).sub(amountArray[2]),
    "amount_get != amount-offcialFeeAmount-partnerFeeAmount");
  } else {
    require(partnerOrderBook[partnerId][borrower][hash].tokenInfoGet.amount == amountArray[0], "amount_get != amount");
  }

  require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_PENDING, "state != ORDER_STATUS_PENDING");

  if (token != address(0)) {
    require(msg.value == 0, "msg.value must be zero for non eth lend");
    require(safeTransferFrom(token, msg.sender, address(this), partnerOrderBook[partnerId][borrower][hash].borrower, partnerOrderBook[partnerId][borrower][hash].tokenInfoGet.amount) == 0,
      "safeTransferFrom to borrower error");
    if (isC2C) {
      require(safeTransferFrom(token, msg.sender, address(this), offcialFeeAccount, amountArray[1]) == 0, "safeTransferFrom to officicalFeeAccount errror");
      require(safeTransferFrom(token, msg.sender, address(this), partnerAccounts[lenderPartnerId], amountArray[2]) == 0, "safeTransferFrom to partnerAccounts[lenderPartnerId] error");
    }
  } else {
      require(amountArray[0] == msg.value, "lenderAmount must be msg.value");
      deposit(lenderPartnerId);
      require(sendEth(lenderPartnerId, partnerOrderBook[partnerId][borrower][hash].borrower.make_payable(), partnerOrderBook[partnerId][borrower][hash].tokenInfoGet.amount),
        "lend: sendEth to borrower error!");
      if (isC2C) {
        require(sendEth(lenderPartnerId, offcialFeeAccount.make_payable(), amountArray[1]), "lend: sendEth to offcial fee error!");
        require(sendEth(lenderPartnerId, partnerAccounts[lenderPartnerId].make_payable(), amountArray[2]), "lend: sendEth to partner error!");
      }
  }
   
  partnerOrderBook[partnerId][borrower][hash].deadline = now.add((partnerOrderBook[partnerId][borrower][hash].rateInfo.pack_data >> 192).mul(1 minutes));
  if (isC2C) {
    partnerOrderBook[partnerId][borrower][hash].lender = msg.sender;
  } else {
    partnerOrderBook[partnerId][borrower][hash].lender = address(this);
  }
  partnerOrderBook[partnerId][borrower][hash].state = OrderState.ORDER_STATUS_ACCEPTED;

  emit Lend(partnerId, lenderPartnerId, borrower, hash, token, amountArray[0], msg.sender);
  return 0;
}

/*
A borrowing, B lending, A's arrival amount is the number of applications, B's lending quantity includes: A's application quantity + handling fee (smart contract handling fee + platform partner fee, handling fee may be 0)
（A借款，B出借，A的到账数量为申请数量，B出借的数量包括：A的申请数量+手续费（智能合约手续费+平台合作方手续费，手续费可能为0））
*/
function c2cLend(MapKey memory mapKey, bytes32 lenderPartnerId, address token, uint256[3] memory amountArray) public payable returns (uint256) {
  return lend(mapKey, lenderPartnerId, token, amountArray, true);
}

function cancelOrder(MapKey memory mapKey) public notNull(mapKey.k1) {
  bytes32 partnerId = mapKey.k1;
  address borrower = mapKey.k2;
  bytes32 hash = mapKey.k3;

  require(partnerOrderBook[partnerId][borrower][hash].borrower != address(0), "order not found");
  require(partnerOrderBook[partnerId][borrower][hash].borrower == msg.sender || msg.sender == admin,
    "only borrower or admin can do this operation");
  require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_PENDING, "state != ORDER_STATUS_PENDING");
  uint status = 1;

  if (partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.token != address(0)) {
    status = sendToken(partnerId, partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.token, partnerOrderBook[partnerId][borrower][hash].borrower, partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.amount);
  } else {
      bool ok = sendEth(partnerId, partnerOrderBook[partnerId][borrower][hash].borrower.make_payable(), partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.amount);
      if (ok) {
          status = 0;
      }
  }

    require(status == 0, "CancelOrder error");
    delete partnerOrderBook[partnerId][borrower][hash];
    deleteHash(partnerId, borrower, hash);
    emit CancelOrder(partnerId, borrower, hash, msg.sender);

}

function callmargin(MapKey memory mapKey, address token, uint256 amount) public notNull(mapKey.k1) payable returns (uint256){
  bytes32 partnerId = mapKey.k1;
  address borrower = mapKey.k2;
  bytes32 hash = mapKey.k3;


  require(partnerOrderBook[partnerId][borrower][hash].borrower != address(0), "order not found");
  require(amount > 0, "amount must >0");

  require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != ORDER_STATUS_ACCEPTED");
  require(partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.token == token, "invalid pledge token");

  if (token != address(0)) {
      require(msg.value == 0, "msg.value must be zero for non eth callmargin");
      require(safeTransferFrom(token, msg.sender, address(this), address(this), amount) == 0, "callmargin safeTransferFrom error");
  } else {
      require(amount == msg.value, "amount must equal msg.value");
  }

  partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.amount = partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.amount.add(amount);
  partnerTokens[partnerId][token][borrower] = partnerTokens[partnerId][token][borrower].add(amount);

  emit Callmargin(partnerId, borrower, hash, token, amount, msg.sender);
  return 0;
}

//When A repays, pay the principal + interest to the lender, and pay the smart contract and platform partner fee.（A还款，需要支付本金+利息给出借方，给合约拥有人和平台合作方手续费）
//lenderAmount: amountArray[0]
//offcialFeeAmount：amountArray[1]
//partnerFeeAmount: amountArray[2]
function repay(MapKey memory mapKey, uint256[3] memory amountArray, bool isC2C) public notNull(mapKey.k1) payable returns (uint256){
  bytes32 partnerId = mapKey.k1;
  address borrower = mapKey.k2;
  bytes32 hash = mapKey.k3;

  address token = partnerOrderBook[partnerId][borrower][hash].tokenInfoGet.token;
  uint256 repayAmount = amountArray[0].add(amountArray[1]).add(amountArray[2]);
  uint256 lenderAmount = amountArray[0];

  require(partnerOrderBook[partnerId][borrower][hash].borrower != address(0), "order not found");
  require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != ORDER_STATUS_ACCEPTED");
  if (!isC2C) {
    repayAmount = amountArray[0];
 }
  require(lenderAmount >= partnerOrderBook[partnerId][borrower][hash].tokenInfoGet.amount, "invalid lender amount");
  require(msg.sender == partnerOrderBook[partnerId][borrower][hash].borrower, "invalid repayer, must be borrower");
  uint status = 1;

  if (token != address(0)) {
      //Allow contract to use the borrower's borrowed token + interest token（允许contract花费借款者的所借的token+利息token）
      require(IERC20(token).allowance(msg.sender, address(this)) >= repayAmount, "repay: Insufficient allowance");
      require(IERC20(token).balanceOf(msg.sender) >= repayAmount, "repay: Insufficient balance");

      IERC20(token).safeTransferFrom(msg.sender, partnerOrderBook[partnerId][borrower][hash].lender, amountArray[0]);
      if (isC2C) {
        IERC20(token).safeTransferFrom(msg.sender, offcialFeeAccount, amountArray[1]);
        IERC20(token).safeTransferFrom(msg.sender, partnerAccounts[partnerId], amountArray[2]);
      }

      if (partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.token != address(0)) {
          status = withdrawToken(partnerId, partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.token, partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.amount);
      } else {
          require(sendEth(partnerId, msg.sender, partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.amount), "sendEth error");
          status = 0;
      }
  } else {
      //Repayment of ETH（还款ETH）
      require(repayAmount == msg.value, "amount must be msg.value");
      deposit(partnerId);
      require(sendEth(partnerId, partnerOrderBook[partnerId][borrower][hash].lender.make_payable(), partnerOrderBook[partnerId][borrower][hash].tokenInfoGet.amount), "repay: send eth to lender error");
      if (isC2C) {
        require(sendEth(partnerId, offcialFeeAccount.make_payable(), amountArray[1]), "repay: send eth to offcial account error");
        require(sendEth(partnerId, partnerAccounts[partnerId].make_payable(), amountArray[2]), "repay: send eth to partner account error");
      }

      status = withdrawToken(partnerId, partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.token, partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.amount);
  }

  require(status == 0, "repay error");
  delete partnerOrderBook[partnerId][borrower][hash];
  deleteHash(partnerId, borrower, hash);
  emit Repay(partnerId, borrower, hash, token, repayAmount, msg.sender);

  return status;
}

function c2cRepay(MapKey memory mapKey, uint256 lenderAmount, uint256 offcialFeeAmount, uint256 partnerFeeAmount) public payable returns (uint256){
  uint256[3] memory x;
  x[0] = lenderAmount;
  x[1] = offcialFeeAmount;
  x[2] = partnerFeeAmount;
  return repay(mapKey, x, true);
}

function fastRepay(MapKey memory mapKey, uint256 lenderAmount) public payable returns (uint256) {
  uint256[3] memory x;
  x[0] = lenderAmount;
  return repay(mapKey, x, false);
}

function liquidation(MapKey memory mapKey, uint256[3] memory amountArray, bool isC2C) internal notNull(mapKey.k1) returns (uint256) {
  bytes32 partnerId = mapKey.k1;
  address borrower = mapKey.k2;
  bytes32 hash = mapKey.k3;
  address token = partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.token;

  require(partnerOrderBook[partnerId][borrower][hash].borrower != address(0), "order not found");
  require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != ORDER_STATUS_ACCEPTED");
  require(msg.sender == admin, "liquidation must be admin");

  if (token != address(0)) {
      //The contract manager sends the pawn asset to the lender, and the amount is passed in from the upper layer.
      //合约管理员发送抵押资产到出借人,数量由上层传入
      partnerTokens[partnerId][token][borrower] = partnerTokens[partnerId][token][borrower].sub(amountArray[0]);
      IERC20(token).safeTransfer(partnerOrderBook[partnerId][borrower][hash].lender, amountArray[0]);

      if (isC2C) {
        //The contract manager sends the pawn asset to the smart contract owner, the amount is passed in from the upper layer
        //合约管理员发送抵押资产到合约拥有人，数量由上层传入
        partnerTokens[partnerId][token][borrower] = partnerTokens[partnerId][token][borrower].sub(amountArray[1]);
        IERC20(token).safeTransfer(offcialFeeAccount, amountArray[1]);

        //The contract manager sends the pawn assets to the platform partner, and the amount is passed in from the upper layer.
        //合约管理员发送抵押资产到平台合作方,数量由上层传入
        partnerTokens[partnerId][token][borrower] = partnerTokens[partnerId][token][borrower].sub(amountArray[2]);
        IERC20(token).safeTransfer(partnerAccounts[partnerId], amountArray[2]);
      }

      //The contract manager sends the remaining pawn assets to the borrower
      //合约管理员发送剩余抵押资产到借款方
      if (partnerTokens[partnerId][token][borrower] > 0) {
          IERC20(token).safeTransfer(borrower, partnerTokens[partnerId][token][borrower]);
      }
  } else {
      //eth pledge
      require(sendEth(partnerId, partnerOrderBook[partnerId][borrower][hash].lender.make_payable(), amountArray[0]), "send eth to lender error");
      if (isC2C) {
        require(sendEth(partnerId, offcialFeeAccount.make_payable(), amountArray[1]), "send eth to offcial account error");
        require(sendEth(partnerId, partnerAccounts[partnerId].make_payable(), amountArray[2]), "send eth to partner account error");
      }

      require(sendEth(partnerId, borrower.make_payable(), partnerTokens[partnerId][token][borrower]), "sendEth to borrower error");
  }

  delete partnerOrderBook[partnerId][borrower][hash];
  deleteHash(partnerId, borrower, hash);

  return 0;
}

function c2cLiquidation(MapKey memory mapKey, uint256[3] memory amountArray) internal returns (uint256) {
  return liquidation(mapKey, amountArray, true);
}

function fastLiquidation(MapKey memory mapKey, uint256[3] memory amountArray) internal returns (uint256) {
  return liquidation(mapKey, amountArray, false);
}

/*
Overdue mandatory return, called by the contract manager, non-borrower, non-lender call,
borrower needs to pay the pawn asset to the borrower (principal + interest), platform partner (handling fee) and smart contract owner (handling fee),
if there is remaining, the rest is returned to A.
（逾期强制归还，由合约管理者调用，非borrower，非lender调用，borrower需要支付抵押资产给出借人（本金+利息），平台合作方（手续费）和项目方（手续费），如果还有剩余，剩余部分归还给A）
*/
function forcerepay(MapKey memory mapKey, uint256[3] memory amountArray, bool isC2C) public notNull(mapKey.k1) returns (uint256){
  bytes32 partnerId = mapKey.k1;
  address borrower = mapKey.k2;
  bytes32 hash = mapKey.k3;

  address token = partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.token;


  require(partnerOrderBook[partnerId][borrower][hash].borrower != address(0), "order not found");
  require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != OrderState.ORDER_STATUS_ACCEPTED");
  require(msg.sender == admin, "forcerepay must be admin");
  require(now > partnerOrderBook[partnerId][borrower][hash].deadline, "cannot forcerepay before deadline");

  if (isC2C) {
    require(liquidation(mapKey, amountArray, isC2C) == 0, "forcerepay error");
    emit Forcerepay(partnerId, borrower, hash, token, msg.sender);
  } else {
    require(fastLiquidation(mapKey, amountArray) == 0, "forcerepay error");
    emit FastForcerepay(partnerId, borrower, hash, token, msg.sender);
  }

  return 0;
}

/*
Overdue mandatory return, called by the contract manager, non-borrower, non-lender call,
borrower needs to pay the pawn asset to the borrower (principal + interest), platform partner (handling fee) and smart contract owner (handling fee),
if there is remaining, the rest is returned to A.
（逾期强制归还，由合约管理者调用，非borrower，非lender调用，borrower需要支付抵押资产给出借人（本金+利息），平台合作方（手续费）和项目方（手续费），如果还有剩余，剩余部分归还给A）
*/
function c2cForcerepay(MapKey memory mapKey, address token, uint256[3] memory amountArray) public returns (uint256){
  return forcerepay(mapKey, amountArray, true);
}

/*
Overdue mandatory return, called by the contract manager, non-borrower, non-lender call,
borrower needs to pay the pawn asset to the borrower (principal + interest), 
if there is remaining, the rest is returned to A.
（逾期强制归还，由合约管理者调用，非borrower，非lender调用，borrower需要支付抵押资产给出借人（本金+利息），如果还有剩余，剩余部分归还给A）
*/
function fastForcerepay(MapKey memory mapKey, address token, uint256[3] memory amountArray) public returns (uint256){
  return forcerepay(mapKey, amountArray, false);
}

/*
The position caused by price fluctuations, the borrower needs to pay the pawn assets to the borrower (principal + interest), the project party (handling fee) and the platform partner (handling fee),
if there is still surplus, the rest is returned to A
价格波动平仓，borrower需要支付抵押资产给出借人（本金+利息），项目方（手续费）和平台合作方（手续费），如果还有剩余，剩余部分归还给A
*/
function closepostion(MapKey memory mapKey, uint256[3] memory amountArray, bool isC2C) public notNull(mapKey.k1) returns (uint256){
  bytes32 partnerId = mapKey.k1;
  address borrower = mapKey.k2;
  bytes32 hash = mapKey.k3;
  address token = partnerOrderBook[partnerId][borrower][hash].tokenInfoGive.token;

  require(partnerOrderBook[partnerId][borrower][hash].borrower != address(0), "order not found");
  require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != OrderState.ORDER_STATUS_ACCEPTED");
  require(msg.sender == admin || msg.sender == partnerOrderBook[partnerId][borrower][hash].lender, "closepostion must be admin or lender");

  //Not overdue（未逾期）
  if (partnerOrderBook[partnerId][borrower][hash].deadline > now) {
    require(msg.sender == admin, "closeposition: only admin of this contract can do this operation before deadline");
  } else {
    require(msg.sender == admin || msg.sender == partnerOrderBook[partnerId][borrower][hash].lender, "closepostion: only lender or admin of this contract can do this operation");
  }

  if (isC2C) {
    liquidation(mapKey, amountArray, isC2C);
    emit Closepostion(partnerId, borrower, hash, token, address(this));
  } else {
    fastLiquidation(mapKey, amountArray);
    emit FastClosepostion(partnerId, borrower, hash, token, address(this));
  }

  return 0;
}

/*
The position caused by price fluctuations, the borrower needs to pay the pawn assets to the borrower (principal + interest), the project party (handling fee) and the platform partner (handling fee),
if there is still surplus, the rest is returned to A
价格波动平仓，borrower需要支付抵押资产给出借人（本金+利息），项目方（手续费）和平台合作方（手续费），如果还有剩余，剩余部分归还给A
*/
function c2cClosepostion(MapKey memory mapKey, uint256[3] memory amountArray) public returns (uint256){
  return closepostion(mapKey, amountArray, true);
}

/*
The position caused by price fluctuations, the borrower needs to pay the pawn assets to the borrower (principal + interest), 
if there is still surplus, the rest is returned to A
价格波动平仓，borrower需要支付抵押资产给出借人（本金+利息），如果还有剩余，剩余部分归还给A
*/
function fastClosepostion(MapKey memory mapKey, uint256[3] memory amountArray) public returns (uint256){
  return closepostion(mapKey, amountArray, false);
}

  //ADDITIONAL HELPERS ADDED FOR TESTING
  function hash(
      bytes32 partnerId,
      address tokenGet,
      uint256 amountGet,
      address tokenGive,
      uint256 amountGive,
      uint256 nonce,
      uint256 packData
  )
      public
      view
      returns (bytes32)
  {
      return sha256(abi.encodePacked(address(this), partnerId, tokenGet, amountGet, tokenGive, amountGive, nonce, packData));
  }
}
