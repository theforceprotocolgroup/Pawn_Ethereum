var InterestRateModel = artifacts.require("InterestRateModel");
var PriceOracles = artifacts.require("PriceOracles");
var PoolPawn = artifacts.require("PoolPawn");

var BigNumber = require('bignumber.js');
var deployenv = require("../deployenv.json");

var fs = require("fs");

var output = 'bank_migrations_init.log';

module.exports = async function (deployer, network) {

    if (fs.existsSync(output)) {
        fs.unlinkSync(output);
    }

    var logger = fs.createWriteStream(output, { flags: 'a' });

    //处理 "rinkeby-fork" 的名字
    network = /([a-z]+)(-fork)?/.exec(network)[1];

    logger.write("init for network: " + network + "\n");

    var env = deployenv[network];
    logger.write("init use env: " + JSON.stringify(env) + "\n");

    const interestRateModel = await InterestRateModel.deployed();
    await interestRateModel.init("18");

    const priceOracles = await PriceOracles.deployed();
    const poolPawn = await PoolPawn.deployed();

    var tokens = env.tokens;
    var promises = [];
    for (let i = 0; i < tokens.length; ++i) {
        let token = tokens[i];

        let discount = BigNumber(token.discount).multipliedBy(1e18).dividedBy(100).toFixed();
        let deposit_multiple = BigNumber(token.deposit_multiple).multipliedBy(1e18).toFixed();

        logger.write("symbol: " + token.symbol + ", address: " + token.address + ", discount: " + discount + "\n");
        logger.write("symbol: " + token.symbol + ", address: " + token.address + ", deposit_multiple: " + deposit_multiple + "\n");

        promises.push(poolPawn.initCollateralMarket(token.address, interestRateModel.address, priceOracles.address, token.decimals));
        promises.push(poolPawn.setMinPledgeRate(token.address, deposit_multiple));
        promises.push(poolPawn.setLiquidationDiscount(token.address, discount));
    }

    await Promise.all(promises);
};