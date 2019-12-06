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

contract IOracle {
  function get(address token) public view returns (uint, bool);
}

contract IInterestRateModel {
  function getLoanRate(int cash, int borrow) public returns (int y);
  function getDepositRate(int cash, int borrow) public returns (int y);

  function calculateBalance(int principal, int lastIndex, int newIndex) public returns (int y);
  function calculateInterestIndex(int Index, int r, int t) public returns (int y);
  function pert(int principal, int r, int t) public returns (int y);
  function continuousCompoundingInterest(int r, int t) public returns (int y);
  function getNewReserve(int oldReserve, int cash, int borrow, int blockDelta) public returns (int y);
  function ert(int r, int t) public returns (int y);
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

    struct Rate {
      int supplyRate;//存款利率
      int demondRate;//借款利率
    }

    /**
      * @notice Container for borrow balance information
      * @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
      * @member interestIndex Global borrowIndex as of the most recent balance-changing action
      */
    //存款/贷款本金和利息
    struct Balance {
        uint principal;
        uint interestIndex;
    }

    struct Market {
      uint accrualBlockNumber;
      Rate rate;

      IInterestRateModel irm;

      uint totalSupply;
      uint supplyIndex;

      uint totalBorrows;
      uint borrowIndex;

      uint totalReserves;//系统盈利

      uint minPledgeRate;//最小质押率
      uint liquidationDiscount;//清算折扣
    }

    mapping (address => mapping (address => Balance)) public accountSupplySnapshot;//tokenContract->address(usr)->SupplySnapshot
    mapping (address => mapping (address => Balance)) public accountBorrowSnapshot;//tokenContract->address(usr)->BorrowSnapshot

    mapping (address => Market) mkts;//tokenAddress->Market
    address[] public collateralTokens;//抵押币种
    address[] public loanTokens;//借贷币种
    IOracle public oracleInstance;

    uint constant initialInterestIndex = 10 ** 18;
    uint constant defaultOriginationFee = 0; // default is zero bps
    uint constant originationFee = 0;
    uint constant ONE_ETH = 1 ether;

    //增加抵押币种，WBTC，ETH，TBTC
    function addCollateralMarket(address asset) public onlyAdmin {
      for (uint i = 0; i < collateralTokens.length; i++) {
        if (collateralTokens[i] == asset) {
          return;
        }
      }
      collateralTokens.push(asset);
    }

    function getCollateralMarketsLength() public view returns (uint) {
      return collateralTokens.length;
    }

    function setInterestRateModel(address t, address irm) public onlyAdmin {
      mkts[t].irm = IInterestRateModel(irm);
    }

    function setMinPledgeRate(address t, uint minPledgeRate) public onlyAdmin {
      mkts[t].minPledgeRate = minPledgeRate;
    }

    function setLiquidationDiscount(address t, uint liquidationDiscount) public onlyAdmin {
      mkts[t].liquidationDiscount = liquidationDiscount;
    }

    function initCollateralMarket(address t, address irm, address oracle) public onlyAdmin {
      if (address(oracleInstance) == address(0)) {
        setOracle(oracle);
      }

      if (address(mkts[t].irm) == address(0)) {
        setInterestRateModel(t, irm);
      }

      addCollateralMarket(t);
      if (mkts[t].supplyIndex == 0) {
        mkts[t].supplyIndex = initialInterestIndex;
      }

      if (mkts[t].borrowIndex == 0) {
        mkts[t].borrowIndex = initialInterestIndex;
      }
    }


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
    require(msg.sender == proposedOfficialFeeAccount, "Not proposed officialfee account");
    offcialFeeAccount = proposedOfficialFeeAccount;
    proposedOfficialFeeAccount = address(0);
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

    //设置USDT，DAI和抵押品的起始时间戳
    function setInitialTimestamp(address token) public onlyAdmin {
      mkts[token].accrualBlockNumber = now;
    }

    function setOracle(address oracle) public onlyAdmin {
      oracleInstance = IOracle(oracle);
    }

    modifier existOracle() {
      require(address(oracleInstance) != address(0), "oracle not set");
      _;
    }

    function fetchAssetPrice(address asset) internal view returns (uint, bool) {
      require(address(oracleInstance) != address(0), "oracle not set");
      return oracleInstance.get(asset);
    }

    function getPriceForAssetAmount(address asset, uint assetAmount) internal view returns (uint) {
      require(address(oracleInstance) != address(0), "oracle not set");
      (uint price, bool ok) = fetchAssetPrice(asset);
      if (ok) {
        return price.mul(assetAmount);
      }
      return 0;
    }

    function getAssetAmountForValue(address t, uint usdValue) internal view returns (uint) {
      require(address(oracleInstance) != address(0), "oracle not set");
      (uint price, bool ok) = fetchAssetPrice(t);
      if (ok) {
        return usdValue.div(price);
      }
      return uint(-1);
    }

    //合约里的现金
    function getCash(address t) public view returns (uint) {
      IERC20 token = IERC20(t);
      return token.balanceOf(address(this));
    }

    function getBalanceOf(address asset, address from) internal view returns (uint) {
      IERC20 token = IERC20(asset);

      return token.balanceOf(from);
    }

    //m:market, a:account
    //i(n,m)=i(n-1,m)*(1+rm*t)
    //return P*(i(n,m)/i(n-1,a))
    function getSupplyBalance(address acc, address t) public returns (uint) {
      Balance storage supplyBalance = accountSupplySnapshot[t][acc];

      int mSupplyIndex = mkts[t].irm.pert(int(mkts[t].supplyIndex), int(mkts[t].rate.supplyRate), int(now - mkts[t].accrualBlockNumber));

      uint userSupplyCurrent = uint(mkts[t].irm.calculateBalance(int(supplyBalance.principal), int(supplyBalance.interestIndex), mSupplyIndex));
      return userSupplyCurrent;
    }

    function getSupplyBalanceInUSD(address who, address t) public returns (uint) {
      return getPriceForAssetAmount(t, getSupplyBalance(who, t));
    }

    //m:market, a:account
    //i(n,m)=i(n-1,m)*(1+rm*t)
    //return P*(i(n,m)/i(n-1,a))
    function getBorrowBalance(address acc, address t) public returns (uint) {
      Balance storage borrowBalance = accountBorrowSnapshot[t][acc];

      int mBorrowIndex = mkts[t].irm.pert(int(mkts[t].borrowIndex), int(mkts[t].rate.demondRate), int(now - mkts[t].accrualBlockNumber));

      uint userBorrowCurrent = uint(mkts[t].irm.calculateBalance(int(borrowBalance.principal), int(borrowBalance.interestIndex), mBorrowIndex));
      return userBorrowCurrent;
    }

    function getBorrowBalanceInUSD(address who, address t) public returns (uint) {
      return getPriceForAssetAmount(t, getBorrowBalance(who, t));
    }

    // BorrowBalance * collateral ratio
    function getBorrowBalanceLeverage(address who, address t) public returns (uint) {
      return getBorrowBalanceInUSD(who,t).mul(mkts[t].minPledgeRate);
    }

    //Gets USD token values of supply and borrow balances
    function calcAccountTokenValuesInternal(address who, address t) internal returns (uint, uint) {
      return (getSupplyBalanceInUSD(who, t), getBorrowBalanceInUSD(who, t));
    }

    //Gets USD token values of supply and borrow balances
    function calcAccountTokenValuesLeverageInternal(address who, address t) internal returns (uint, uint) {
      return (getSupplyBalanceInUSD(who, t), getBorrowBalanceLeverage(who, t));
    }

    //Gets USD all token values of supply and borrow balances
    function calcAccountAllTokenValuesLeverageInternal(address who) internal returns (uint, uint) {
      uint length = collateralTokens.length;
      uint sumSupplies;
      uint sumBorrowLeverage;

      for (uint i = 0; i < length; i++) {
        (uint supplyValue, uint borrowsLeverage) = calcAccountTokenValuesLeverageInternal(who, collateralTokens[i]);
        sumSupplies += supplyValue;
        sumBorrowLeverage += borrowsLeverage;
      }
      return (sumSupplies, sumBorrowLeverage);
    }

    function calcAccountLiquidity(address who) internal returns (uint, uint) {
      uint sumSupplies;
      uint sumBorrowsLeverage;//sumBorrows* collateral ratio
      (sumSupplies, sumBorrowsLeverage) = calcAccountAllTokenValuesLeverageInternal(who);
      if (sumSupplies < sumBorrowsLeverage) {
        return (0, sumBorrowsLeverage.sub(sumSupplies));//不足
      } else {
        return (sumSupplies.sub(sumBorrowsLeverage), 0);//有余
      }
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

function _withdrawAsset(bytes32 partnerId, address token, address to, uint256 amount, bool transferInterest) internal notNull(partnerId) returns (uint256) {
  require(token != address(0) && to != address(0) && amount != 0, "invalid token address or amount");

  partnerTokens[partnerId][token][to] = partnerTokens[partnerId][token][to].sub(amount);
  IERC20(token).safeTransfer(to, amount);

  return 0;
}

//Withdrawal of deposits and interest（提现存款和利息）
function withdrawSavings(bytes32 partnerId, address token, uint256 amount) public returns (uint256) {
  _withdrawAsset(partnerId, token, msg.sender, amount, true);
  emit WithdrawSavings(partnerId, token, amount);

  return 0;
}

  struct SupplyIR {
      uint startingBalance;
      uint newSupplyIndex;
      uint userSupplyCurrent;
      uint userSupplyUpdated;
      uint newTotalSupply;
      uint currentCash;
      uint updatedCash;
      uint newBorrowIndex;
  }

  function supplyPawn(address t, uint amount) public returns (uint) {
    SupplyIR memory tmp;
    Market storage market = mkts[t];
    Balance storage supplyBalance = accountSupplySnapshot[t][msg.sender];

    uint lastTimestamp = mkts[t].accrualBlockNumber;
    uint blockDelta = now - lastTimestamp;

    tmp.newSupplyIndex = uint(mkts[t].irm.pert(int(mkts[t].supplyIndex), int(mkts[t].rate.supplyRate), int(blockDelta)));
    tmp.userSupplyCurrent = uint(mkts[t].irm.calculateBalance(int(accountSupplySnapshot[t][msg.sender].principal), int(supplyBalance.interestIndex), int(tmp.newSupplyIndex)));
    tmp.userSupplyUpdated = tmp.userSupplyCurrent.add(amount);
    tmp.newTotalSupply = market.totalSupply.add(tmp.userSupplyUpdated).sub(supplyBalance.principal);

    tmp.currentCash = getCash(t);
    tmp.updatedCash = tmp.currentCash.add(amount);

    mkts[t].rate.supplyRate = mkts[t].irm.getDepositRate(int(tmp.updatedCash), int(mkts[t].totalBorrows));
    tmp.newBorrowIndex = uint(mkts[t].irm.pert(int(mkts[t].borrowIndex), int(mkts[t].rate.demondRate), int(blockDelta)));
    mkts[t].rate.demondRate = mkts[t].irm.getLoanRate(int(tmp.updatedCash), int(mkts[t].totalBorrows));

    require(safeTransferFrom(t, msg.sender, address(this), address(this), amount) == 0, "supply error");

    mkts[t].borrowIndex = tmp.newBorrowIndex;
    mkts[t].supplyIndex = tmp.newSupplyIndex;
    mkts[t].totalSupply = tmp.newTotalSupply;
    mkts[t].accrualBlockNumber = now;

    supplyBalance.principal = tmp.userSupplyUpdated;
    supplyBalance.interestIndex = tmp.newSupplyIndex;
  }

  struct WithdrawIR {
    uint withdrawAmount;
    uint startingBalance;
    uint newSupplyIndex;
    uint userSupplyCurrent;
    uint userSupplyUpdated;
    uint newTotalSupply;
    uint currentCash;
    uint updatedCash;
    uint newBorrowIndex;

    uint accountLiquidity;
    uint accountShortfall;
    uint usdValueOfWithdrawal;
    uint withdrawCapacity;
  }

  function withdrawPawn(address t, uint requestedAmount) public returns (uint) {
    Market storage market = mkts[t];
    Balance storage supplyBalance = accountSupplySnapshot[t][msg.sender];

    WithdrawIR memory tmp;

    uint lastTimestamp = mkts[t].accrualBlockNumber;
    uint blockDelta = now - lastTimestamp;

    (tmp.accountLiquidity, tmp.accountShortfall) = calcAccountLiquidity(msg.sender);
    require(tmp.accountShortfall == 0, "can't withdraw, shortfall");
    tmp.newSupplyIndex = uint(mkts[t].irm.pert(int(mkts[t].supplyIndex), int(mkts[t].rate.supplyRate), int(blockDelta)));
    tmp.userSupplyCurrent = uint(mkts[t].irm.calculateBalance(int(supplyBalance.principal), int(supplyBalance.interestIndex), int(tmp.newSupplyIndex)));

    if (requestedAmount == uint(-1)) {
      tmp.withdrawCapacity = getAssetAmountForValue(t, tmp.accountLiquidity);
      tmp.withdrawAmount = min(tmp.withdrawCapacity, tmp.userSupplyCurrent);
    } else {
      tmp.withdrawAmount = requestedAmount;
    }

    tmp.currentCash = getCash(t);
    tmp.updatedCash = tmp.currentCash.sub(tmp.withdrawAmount);
    tmp.userSupplyUpdated = tmp.userSupplyCurrent.sub(tmp.withdrawAmount);

    tmp.usdValueOfWithdrawal = getPriceForAssetAmount(t, tmp.withdrawAmount);
    require(tmp.usdValueOfWithdrawal <= tmp.accountLiquidity);

    tmp.newTotalSupply = market.totalSupply.add(tmp.userSupplyUpdated).sub(supplyBalance.principal);

    tmp.newSupplyIndex = uint(mkts[t].irm.pert(int(mkts[t].supplyIndex), int(mkts[t].rate.supplyRate), int(blockDelta)));

    market.rate.supplyRate = mkts[t].irm.getDepositRate(int(tmp.updatedCash), int(market.totalBorrows));
    tmp.newBorrowIndex = uint(mkts[t].irm.pert(int(mkts[t].borrowIndex), mkts[t].rate.demondRate, int(blockDelta)));
    market.rate.demondRate = mkts[t].irm.getLoanRate(int(tmp.updatedCash), int(market.totalBorrows));

    safeTransferFrom(t, address(this), address(this), msg.sender, tmp.withdrawAmount);

    market.accrualBlockNumber = now;
    market.totalSupply = tmp.newTotalSupply;
    market.supplyIndex = tmp.newSupplyIndex;
    market.borrowIndex = tmp.newBorrowIndex;

    supplyBalance.principal = tmp.userSupplyUpdated;
    supplyBalance.interestIndex = tmp.newSupplyIndex;
  }

  struct PayBorrowIR {
    uint newBorrowIndex;
    uint userBorrowCurrent;
    uint repayAmount;

    uint userBorrowUpdated;
    uint newTotalBorrows;
    uint currentCash;
    uint updatedCash;

    uint newSupplyIndex;

    uint startingBalance;
  }

  function min(uint a, uint b) pure internal returns (uint) {
    if (a < b) {
        return a;
    } else {
        return b;
    }
  }

  //`(1 + originationFee) * borrowAmount`
  function calcBorrowAmountWithFee(uint borrowAmount) internal view returns (uint) {
    return borrowAmount.mul((ONE_ETH).add(originationFee));
  }

  function getPriceForAssetAmountMulCollatRatio(address t, uint assetAmount) internal view returns (uint) {
    return getPriceForAssetAmount(t, assetAmount).mul(mkts[t].minPledgeRate);
  }

  struct BorrowIR {
    uint newBorrowIndex;
    uint userBorrowCurrent;
    uint borrowAmountWithFee;

    uint userBorrowUpdated;
    uint newTotalBorrows;
    uint currentCash;
    uint updatedCash;

    uint newSupplyIndex;

    uint startingBalance;

    uint accountLiquidity;
    uint accountShortfall;
    uint usdValueOfBorrowAmountWithFee;
  }

  function BorrowPawn(address t, uint amount) public returns (uint) {
    BorrowIR memory tmp;
    Market storage market = mkts[t];
    Balance storage borrowBalance = accountBorrowSnapshot[t][msg.sender];

    uint lastTimestamp = mkts[t].accrualBlockNumber;
    uint blockDelta = now - lastTimestamp;

    tmp.newBorrowIndex = uint(mkts[t].irm.pert(int(mkts[t].borrowIndex), mkts[t].rate.demondRate, int(blockDelta)));
    int lastIndex = int(borrowBalance.interestIndex);
    tmp.userBorrowCurrent = uint(mkts[t].irm.calculateBalance(int(borrowBalance.principal), lastIndex, int(tmp.newBorrowIndex)));
    tmp.borrowAmountWithFee = calcBorrowAmountWithFee(amount);

    tmp.userBorrowUpdated = tmp.userBorrowCurrent.add(tmp.borrowAmountWithFee);
    tmp.newTotalBorrows = market.totalBorrows.add(tmp.userBorrowUpdated).sub(borrowBalance.principal);

    (tmp.accountLiquidity, tmp.accountShortfall) = calcAccountLiquidity(msg.sender);
    require(tmp.accountShortfall == 0, "can't borrow, shortfall");

    tmp.usdValueOfBorrowAmountWithFee = getPriceForAssetAmountMulCollatRatio(t, tmp.borrowAmountWithFee);
    require(tmp.usdValueOfBorrowAmountWithFee <= tmp.accountLiquidity, "can't borrow, without enough value");

    tmp.currentCash = getCash(t);
    tmp.updatedCash = tmp.currentCash.sub(amount);

    tmp.newSupplyIndex = uint(mkts[t].irm.pert(int(mkts[t].supplyIndex), int(mkts[t].rate.supplyRate), int(blockDelta)));
    market.rate.supplyRate = mkts[t].irm.getDepositRate(int(tmp.updatedCash), int(tmp.newTotalBorrows));
    market.rate.demondRate = mkts[t].irm.getLoanRate(int(tmp.updatedCash), int(tmp.newTotalBorrows));

    safeTransferFrom(t, address(this), address(this), msg.sender, amount);

    market.accrualBlockNumber = now;
    market.totalBorrows = tmp.newTotalBorrows;
    market.supplyIndex = tmp.newSupplyIndex;
    market.borrowIndex = tmp.newBorrowIndex;

    borrowBalance.principal = tmp.userBorrowUpdated;
    borrowBalance.interestIndex = tmp.newBorrowIndex;
  }

  //t: token
  function repayFastBorrow(address t, uint amount) public returns (uint) {
    PayBorrowIR memory tmp;
    Market storage market = mkts[t];
    Balance storage borrowBalance = accountBorrowSnapshot[t][msg.sender];

    uint lastTimestamp = mkts[t].accrualBlockNumber;
    uint blockDelta = now - lastTimestamp;

    tmp.newBorrowIndex = uint(mkts[t].irm.pert(int(mkts[t].borrowIndex), mkts[t].rate.demondRate, int(blockDelta)));

    int lastIndex = int(borrowBalance.interestIndex);
    tmp.userBorrowCurrent = uint(mkts[t].irm.calculateBalance(int(borrowBalance.principal), lastIndex, int(tmp.newBorrowIndex)));

    if (amount == uint(-1)) {
        tmp.repayAmount = min(getBalanceOf(t, msg.sender), tmp.userBorrowCurrent);
    } else {
        tmp.repayAmount = amount;
    }

    tmp.userBorrowUpdated = tmp.userBorrowCurrent.sub(tmp.repayAmount);
    tmp.newTotalBorrows = market.totalBorrows.add(tmp.userBorrowUpdated).sub(borrowBalance.principal);
    tmp.currentCash = getCash(t);
    tmp.updatedCash = tmp.currentCash.add(tmp.repayAmount);

    tmp.newSupplyIndex = uint(mkts[t].irm.pert(int(mkts[t].supplyIndex), int(mkts[t].rate.supplyRate), int(blockDelta)));
    market.rate.supplyRate = mkts[t].irm.getDepositRate(int(tmp.updatedCash), int(tmp.newTotalBorrows));
    market.rate.demondRate = mkts[t].irm.getLoanRate(int(tmp.updatedCash), int(tmp.newTotalBorrows));

    safeTransferFrom(t, msg.sender, address(this), address(this), tmp.repayAmount);

    market.accrualBlockNumber = now;
    market.totalBorrows = tmp.newTotalBorrows;
    market.supplyIndex = tmp.newSupplyIndex;
    market.borrowIndex = tmp.newBorrowIndex;

    borrowBalance.principal = tmp.userBorrowUpdated;
    borrowBalance.interestIndex = tmp.newBorrowIndex;
  }

  //shortfall/(price*(minPledgeRate-liquidationDiscount-1))
  //liquidationDiscount是清算折扣, in QIAN, 无清算折扣，但有罚金，罚金是8%，无清算折扣
  //underwaterAsset is borrowAsset
  function calcDiscountedRepayToEvenAmount(address targetAccount, address underwaterAsset, uint underwaterAssetPrice) internal returns (uint) {
    (, uint shortfall) = calcAccountLiquidity(targetAccount);
    uint minPledgeRate = mkts[underwaterAsset].minPledgeRate;
    uint liquidationDiscount = mkts[underwaterAsset].liquidationDiscount;
    uint gap = minPledgeRate.sub(liquidationDiscount).sub(1 ether);
    return shortfall.div(underwaterAssetPrice.mul(gap));
  }

  //[supplyCurrent / (1 + liquidationDiscount)] * (Oracle price for the collateral / Oracle price for the borrow)
  //[supplyCurrent * (Oracle price for the collateral)] / [ (1 + liquidationDiscount) * (Oracle price for the borrow) ]
  function calcDiscountedBorrowDenominatedCollateral(address underwaterAsset, uint underwaterAssetPrice, uint collateralPrice, uint supplyCurrent_TargetCollateralAsset) view internal returns (uint) {
    uint liquidationDiscount = mkts[underwaterAsset].liquidationDiscount;
    uint onePlusLiquidationDiscount = (ONE_ETH).add(liquidationDiscount);
    uint supplyCurrentTimesOracleCollateral = supplyCurrent_TargetCollateralAsset.mul(collateralPrice);
    return supplyCurrentTimesOracleCollateral.div(onePlusLiquidationDiscount.mul(underwaterAssetPrice));
  }

  //closeBorrowAmount_TargetUnderwaterAsset * (1+liquidationDiscount) * priceBorrow/priceCollateral
  //underwaterAssetPrice * (1+liquidationDiscount) *closeBorrowAmount_TargetUnderwaterAsset) / collateralPrice
  //underwater is borrow
  function calcAmountSeize(address underwaterAsset, uint underwaterAssetPrice, uint collateralPrice, uint closeBorrowAmount_TargetUnderwaterAsset) internal view returns (uint) {
    uint liquidationDiscount = mkts[underwaterAsset].liquidationDiscount;
    uint onePlusLiquidationDiscount = (ONE_ETH).add(liquidationDiscount);
    return underwaterAssetPrice.mul(onePlusLiquidationDiscount).mul(closeBorrowAmount_TargetUnderwaterAsset).div(collateralPrice);
  }

  struct LiquidateIR {
    // we need these addresses in the struct for use with `emitLiquidationEvent` to avoid `CompilerError: Stack too deep, try removing local variables.`
    address targetAccount;
    address assetBorrow;
    address liquidator;
    address assetCollateral;

    // borrow index and supply index are global to the asset, not specific to the user
    uint newBorrowIndex_UnderwaterAsset;
    uint newSupplyIndex_UnderwaterAsset;
    uint newBorrowIndex_CollateralAsset;
    uint newSupplyIndex_CollateralAsset;

    // the target borrow's full balance with accumulated interest
    uint currentBorrowBalance_TargetUnderwaterAsset;
    // currentBorrowBalance_TargetUnderwaterAsset minus whatever gets repaid as part of the liquidation
    uint updatedBorrowBalance_TargetUnderwaterAsset;

    uint newTotalBorrows_ProtocolUnderwaterAsset;

    uint startingBorrowBalance_TargetUnderwaterAsset;
    uint startingSupplyBalance_TargetCollateralAsset;
    uint startingSupplyBalance_LiquidatorCollateralAsset;

    uint currentSupplyBalance_TargetCollateralAsset;
    uint updatedSupplyBalance_TargetCollateralAsset;

    // If liquidator already has a balance of collateralAsset, we will accumulate
    // interest on it before transferring seized collateral from the borrower.
    uint currentSupplyBalance_LiquidatorCollateralAsset;
    // This will be the liquidator's accumulated balance of collateral asset before the liquidation (if any)
    // plus the amount seized from the borrower.
    uint updatedSupplyBalance_LiquidatorCollateralAsset;

    uint newTotalSupply_ProtocolCollateralAsset;
    uint currentCash_ProtocolUnderwaterAsset;
    uint updatedCash_ProtocolUnderwaterAsset;

    // cash does not change for collateral asset

    //mkts[t].rate
    uint newSupplyRateMantissa_ProtocolUnderwaterAsset;
    uint newBorrowRateMantissa_ProtocolUnderwaterAsset;

    // Why no variables for the interest rates for the collateral asset?
    // We don't need to calculate new rates for the collateral asset since neither cash nor borrows change

    uint discountedRepayToEvenAmount;

    //[supplyCurrent / (1 + liquidationDiscount)] * (Oracle price for the collateral / Oracle price for the borrow) (discountedBorrowDenominatedCollateral)
    uint discountedBorrowDenominatedCollateral;

    uint maxCloseableBorrowAmount_TargetUnderwaterAsset;
    uint closeBorrowAmount_TargetUnderwaterAsset;
    uint seizeSupplyAmount_TargetCollateralAsset;

    uint collateralPrice;
    uint underwaterAssetPrice;
  }


  function liquidateBorrowPawn(address targetAccount, address assetBorrow, address assetCollateral, uint requestedAmountClose) public returns (uint) {
        LiquidateIR memory tmp;
        // Copy these addresses into the struct for use with `emitLiquidationEvent`
        // We'll use tmp.liquidator inside this function for clarity vs using msg.sender.
        tmp.targetAccount = targetAccount;
        tmp.assetBorrow = assetBorrow;
        tmp.liquidator = msg.sender;
        tmp.assetCollateral = assetCollateral;

        uint lastTimestamp = mkts[assetBorrow].accrualBlockNumber;
        uint blockDelta = now - lastTimestamp;

        Market storage borrowMarket = mkts[assetBorrow];
        Market storage collateralMarket = mkts[assetCollateral];
        Balance storage borrowBalance_TargeUnderwaterAsset = accountBorrowSnapshot[assetBorrow][targetAccount];
        Balance storage supplyBalance_TargetCollateralAsset = accountSupplySnapshot[assetCollateral][targetAccount];

        // Liquidator might already hold some of the collateral asset
        Balance storage supplyBalance_LiquidatorCollateralAsset = accountSupplySnapshot[assetCollateral][tmp.liquidator];

        bool ok;
        (tmp.collateralPrice, ok) = fetchAssetPrice(assetCollateral);
        require(ok, "fail to get collateralPrice");

        (tmp.underwaterAssetPrice, ok) = fetchAssetPrice(assetBorrow);
        require(ok, "fail to get underwaterAssetPrice");

        tmp.newBorrowIndex_UnderwaterAsset = uint(borrowMarket.irm.pert(int(borrowMarket.borrowIndex), borrowMarket.rate.demondRate, int(blockDelta)));
        tmp.currentBorrowBalance_TargetUnderwaterAsset = uint(borrowMarket.irm.calculateBalance(int(borrowBalance_TargeUnderwaterAsset.principal), int(borrowBalance_TargeUnderwaterAsset.interestIndex), int(tmp.newBorrowIndex_UnderwaterAsset)));

        tmp.newSupplyIndex_CollateralAsset = uint(collateralMarket.irm.pert(int(collateralMarket.supplyIndex), collateralMarket.rate.supplyRate, int(blockDelta)));
        tmp.currentSupplyBalance_TargetCollateralAsset = uint(collateralMarket.irm.calculateBalance(int(supplyBalance_TargetCollateralAsset.principal), int(supplyBalance_TargetCollateralAsset.interestIndex), int(tmp.newSupplyIndex_CollateralAsset)));

        tmp.currentSupplyBalance_LiquidatorCollateralAsset = uint(collateralMarket.irm.calculateBalance(int(supplyBalance_LiquidatorCollateralAsset.principal), int(supplyBalance_LiquidatorCollateralAsset.interestIndex), int(tmp.newSupplyIndex_CollateralAsset)));

        tmp.newTotalSupply_ProtocolCollateralAsset = collateralMarket.totalSupply.add(tmp.currentSupplyBalance_TargetCollateralAsset).sub(supplyBalance_TargetCollateralAsset.principal);
        tmp.newTotalSupply_ProtocolCollateralAsset = tmp.newTotalSupply_ProtocolCollateralAsset.add(tmp.currentSupplyBalance_LiquidatorCollateralAsset).sub(supplyBalance_LiquidatorCollateralAsset.principal);

        tmp.discountedBorrowDenominatedCollateral = calcDiscountedBorrowDenominatedCollateral(assetBorrow, tmp.underwaterAssetPrice, tmp.collateralPrice, tmp.currentSupplyBalance_TargetCollateralAsset);
        tmp.discountedRepayToEvenAmount = calcDiscountedRepayToEvenAmount(targetAccount, assetBorrow, tmp.underwaterAssetPrice);
        tmp.maxCloseableBorrowAmount_TargetUnderwaterAsset = min(tmp.currentBorrowBalance_TargetUnderwaterAsset, tmp.discountedBorrowDenominatedCollateral);
        tmp.maxCloseableBorrowAmount_TargetUnderwaterAsset = min(tmp.maxCloseableBorrowAmount_TargetUnderwaterAsset, tmp.discountedRepayToEvenAmount);

        if (requestedAmountClose == uint(-1)) {
            tmp.closeBorrowAmount_TargetUnderwaterAsset = tmp.maxCloseableBorrowAmount_TargetUnderwaterAsset;
        } else {
            tmp.closeBorrowAmount_TargetUnderwaterAsset = requestedAmountClose;
        }
        require(tmp.closeBorrowAmount_TargetUnderwaterAsset <= tmp.maxCloseableBorrowAmount_TargetUnderwaterAsset, "closeBorrowAmount > maxCloseableBorrowAmount err");

        tmp.seizeSupplyAmount_TargetCollateralAsset = calcAmountSeize(assetBorrow, tmp.underwaterAssetPrice, tmp.collateralPrice, tmp.closeBorrowAmount_TargetUnderwaterAsset);

        require(getBalanceOf(assetBorrow, tmp.liquidator) <= tmp.closeBorrowAmount_TargetUnderwaterAsset, "insufficient balance");
        tmp.updatedBorrowBalance_TargetUnderwaterAsset = tmp.currentBorrowBalance_TargetUnderwaterAsset.sub(tmp.closeBorrowAmount_TargetUnderwaterAsset);
        tmp.newTotalBorrows_ProtocolUnderwaterAsset = borrowMarket.totalBorrows.add(tmp.updatedBorrowBalance_TargetUnderwaterAsset).sub(borrowBalance_TargeUnderwaterAsset.principal);

        tmp.currentCash_ProtocolUnderwaterAsset = getCash(assetBorrow);
        tmp.updatedCash_ProtocolUnderwaterAsset = tmp.currentCash_ProtocolUnderwaterAsset.add(tmp.closeBorrowAmount_TargetUnderwaterAsset);

        tmp.newSupplyIndex_UnderwaterAsset = uint(borrowMarket.irm.pert(int(borrowMarket.supplyIndex), borrowMarket.rate.demondRate, int(blockDelta)));
        borrowMarket.rate.supplyRate = borrowMarket.irm.getDepositRate(int(tmp.updatedCash_ProtocolUnderwaterAsset), int(tmp.newTotalBorrows_ProtocolUnderwaterAsset));
        borrowMarket.rate.demondRate = borrowMarket.irm.getLoanRate(int(tmp.updatedCash_ProtocolUnderwaterAsset), int(tmp.newTotalBorrows_ProtocolUnderwaterAsset));
        tmp.newBorrowIndex_CollateralAsset = uint(collateralMarket.irm.pert(int(collateralMarket.supplyIndex), collateralMarket.rate.demondRate, int(blockDelta)));

        tmp.updatedSupplyBalance_TargetCollateralAsset = tmp.currentSupplyBalance_TargetCollateralAsset.sub(tmp.seizeSupplyAmount_TargetCollateralAsset);
        tmp.updatedSupplyBalance_LiquidatorCollateralAsset = tmp.currentSupplyBalance_LiquidatorCollateralAsset.add(tmp.seizeSupplyAmount_TargetCollateralAsset);

        safeTransferFrom(assetBorrow, tmp.liquidator, address(this), address(this), tmp.closeBorrowAmount_TargetUnderwaterAsset);

        borrowMarket.accrualBlockNumber = now;
        borrowMarket.totalBorrows = tmp.newTotalBorrows_ProtocolUnderwaterAsset;
        borrowMarket.supplyIndex = tmp.newSupplyIndex_UnderwaterAsset;
        borrowMarket.borrowIndex = tmp.newBorrowIndex_UnderwaterAsset;

        collateralMarket.accrualBlockNumber = now;
        collateralMarket.totalSupply = tmp.newTotalSupply_ProtocolCollateralAsset;
        collateralMarket.supplyIndex = tmp.newSupplyIndex_CollateralAsset;
        collateralMarket.borrowIndex = tmp.newBorrowIndex_CollateralAsset;

        tmp.startingBorrowBalance_TargetUnderwaterAsset = borrowBalance_TargeUnderwaterAsset.principal; // save for use in event
        borrowBalance_TargeUnderwaterAsset.principal = tmp.updatedBorrowBalance_TargetUnderwaterAsset;
        borrowBalance_TargeUnderwaterAsset.interestIndex = tmp.newBorrowIndex_UnderwaterAsset;

        tmp.startingSupplyBalance_TargetCollateralAsset = supplyBalance_TargetCollateralAsset.principal; // save for use in event
        supplyBalance_TargetCollateralAsset.principal = tmp.updatedSupplyBalance_TargetCollateralAsset;
        supplyBalance_TargetCollateralAsset.interestIndex = tmp.newSupplyIndex_CollateralAsset;

        tmp.startingSupplyBalance_LiquidatorCollateralAsset = supplyBalance_LiquidatorCollateralAsset.principal; // save for use in event
        supplyBalance_LiquidatorCollateralAsset.principal = tmp.updatedSupplyBalance_LiquidatorCollateralAsset;
        supplyBalance_LiquidatorCollateralAsset.interestIndex = tmp.newSupplyIndex_CollateralAsset;

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
  require(partnerOrderBook[partnerId][borrower][hash].tokenInfoGet.token == token, "invalid type of token");
  if (isC2C) {
    //Insufficient single lending amount, we will consider introducing multiple lenders in the future, and now only consider one lender（单个出借金额不足，后续可以考虑多个出借人，现在只考虑一个出借人）
    require(partnerOrderBook[partnerId][borrower][hash].tokenInfoGet.amount == amountArray[0].sub(amountArray[1]).sub(amountArray[2]),
    "amountArray set error");
  } else {
    require(partnerOrderBook[partnerId][borrower][hash].tokenInfoGet.amount == amountArray[0], "amount_get != amount");
  }

  require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_PENDING, "state != ORDER_STATUS_PENDING");

  if (token != address(0)) {
    require(msg.value == 0, "value must be zero for erc lend");
    require(safeTransferFrom(token, msg.sender, address(this), partnerOrderBook[partnerId][borrower][hash].borrower, partnerOrderBook[partnerId][borrower][hash].tokenInfoGet.amount) == 0,
      "tx to borrower err");
    if (isC2C) {
      require(safeTransferFrom(token, msg.sender, address(this), offcialFeeAccount, amountArray[1]) == 0, "tx to officicalFeeAccount err");
      require(safeTransferFrom(token, msg.sender, address(this), partnerAccounts[lenderPartnerId], amountArray[2]) == 0, "tx to lender partner account err");
    }
  } else {
      require(amountArray[0] == msg.value, "lenderAmount must be msg.value");
      deposit(lenderPartnerId);
      require(sendEth(lenderPartnerId, partnerOrderBook[partnerId][borrower][hash].borrower.make_payable(), partnerOrderBook[partnerId][borrower][hash].tokenInfoGet.amount),
        "lend: sendEth to borrower err");
      if (isC2C) {
        require(sendEth(lenderPartnerId, offcialFeeAccount.make_payable(), amountArray[1]), "lend: sendEth to offcial fee err");
        require(sendEth(lenderPartnerId, partnerAccounts[lenderPartnerId].make_payable(), amountArray[2]), "lend: sendEth to partner err");
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
    "require borrower or admin");
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
      require(msg.value == 0, "value must be zero for erc margin");
      require(safeTransferFrom(token, msg.sender, address(this), address(this), amount) == 0, "callmargin tx err");
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
  require(msg.sender == partnerOrderBook[partnerId][borrower][hash].borrower, "msg.sender must be borrower");
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
        require(sendEth(partnerId, offcialFeeAccount.make_payable(), amountArray[1]), "repay eth to offcial account err");
        require(sendEth(partnerId, partnerAccounts[partnerId].make_payable(), amountArray[2]), "repay eth to partner account err");
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
      require(sendEth(partnerId, partnerOrderBook[partnerId][borrower][hash].lender.make_payable(), amountArray[0]), "send eth to lender err");
      if (isC2C) {
        require(sendEth(partnerId, offcialFeeAccount.make_payable(), amountArray[1]), "send eth to offcial account err");
        require(sendEth(partnerId, partnerAccounts[partnerId].make_payable(), amountArray[2]), "send eth to partner account err");
      }

      require(sendEth(partnerId, borrower.make_payable(), partnerTokens[partnerId][token][borrower]), "sendEth to borrower err");
  }

  delete partnerOrderBook[partnerId][borrower][hash];
  deleteHash(partnerId, borrower, hash);

  return 0;
}

function c2cLiquidation(MapKey memory mapKey, uint256[3] memory amountArray) internal returns (uint256) {
  return liquidation(mapKey, amountArray, true);
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
  require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != ORDER_STATUS_ACCEPTED");
  require(msg.sender == admin, "forcerepay must be admin");
  require(now > partnerOrderBook[partnerId][borrower][hash].deadline, "can't forcerepay before deadline");

  if (isC2C) {
    require(liquidation(mapKey, amountArray, isC2C) == 0, "forcerepay error");
    emit Forcerepay(partnerId, borrower, hash, token, msg.sender);
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
  require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != ORDER_STATUS_ACCEPTED");
  require(msg.sender == admin || msg.sender == partnerOrderBook[partnerId][borrower][hash].lender, "sender must be admin or lender");

  //Not overdue（未逾期）
  if (partnerOrderBook[partnerId][borrower][hash].deadline > now) {
    require(msg.sender == admin, "only admin can close before DDL");
  } else {
    require(msg.sender == admin || msg.sender == partnerOrderBook[partnerId][borrower][hash].lender, "only lender or admin can close");
  }

  if (isC2C) {
    liquidation(mapKey, amountArray, isC2C);
    emit Closepostion(partnerId, borrower, hash, token, address(this));
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
