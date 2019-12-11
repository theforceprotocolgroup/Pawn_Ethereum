/*
 * Copyright (c) The Force Protocol Development Team
 * Submitted for verification at Etherscan.io on 2019-09-17
*/

pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;


import "./SafeERC20.sol";

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

contract PoolPawn {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using address_make_payable for address;

    address public admin; //the admin address
    address public proposedAdmin;//use pull over push pattern for admin

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

constructor(address admin_) public {
  admin = admin_;
}

function() external payable {
  revert("fallback can't be payable");
}

modifier onlyAdmin() {
  require(msg.sender == admin, "only admin can do this!");
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

}
