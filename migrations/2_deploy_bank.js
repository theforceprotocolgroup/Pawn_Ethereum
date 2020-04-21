var FixidityLib = artifacts.require("FixidityLib");
var LogarithmLib = artifacts.require("LogarithmLib");
var ExponentLib = artifacts.require("ExponentLib");
var InterestRateModel = artifacts.require("InterestRateModel");
var PriceOracles = artifacts.require("PriceOracles");
var PoolPawn = artifacts.require("PoolPawn");
// var Config = artifacts.require("Config");
// var Oracle = artifacts.require("Oracle");
// var Verify = artifacts.require("Verify");

// var ACL = artifacts.require("ACL");
// var BondFactory = artifacts.require("BondFactory");
// var NameGen = artifacts.require("NameGen");
// var PRA = artifacts.require("PRA");
// var CoreUtils = artifacts.require("CoreUtils");

var BigNumber = require("bignumber.js");

var fs = require("fs");

// var deployenv = require("../deployenv.json");

module.exports = async function(deployer, network) {
    network = /([a-z]+)(-fork)?/.exec(network)[1];
    var output = './deployed_' + network + ".json";
    if(fs.existsSync(output)) {
        fs.unlinkSync(output);
    }

    // var gov = deployenv[network].gov;
    // var pra_deposit_line = deployenv[network].pra_deposit_line;

    // let gov_decimals = BigNumber(10).pow(gov.decimals);
    // pra_deposit_line = BigNumber(pra_deposit_line).multipliedBy(gov_decimals).toFixed();

    await deployer.deploy(FixidityLib);
    await deployer.link(FixidityLib, LogarithmLib);
    await deployer.deploy(LogarithmLib);
    await deployer.link(LogarithmLib, ExponentLib);
    await deployer.link(FixidityLib, ExponentLib);
    await deployer.deploy(ExponentLib);

    await deployer.link(FixidityLib, InterestRateModel);
    await deployer.link(LogarithmLib, InterestRateModel);
    await deployer.link(ExponentLib, InterestRateModel);
    await deployer.deploy(InterestRateModel);

    await deployer.deploy(PriceOracles);
    await deployer.deploy(PoolPawn);
    // await deployer.deploy(Oracle, ACL.address);
    // await deployer.deploy(Config, ACL.address);
    // await deployer.deploy(Verify, Config.address);
    // await deployer.deploy(Vote, ACL.address, Router.address, Config.address, PRA.address);

    // await deployer.deploy(NameGen);
    // await deployer.deploy(CoreUtils, Router.address, Oracle.address);

    // await deployer.deploy(Core, ACL.address, Router.address, Config.address, CoreUtils.address, Oracle.address, NameGen.address);
    // await deployer.deploy(BondFactory, ACL.address, Router.address, Verify.address, Vote.address, Core.address, NameGen.address);
    
    var deployed = {
        FixidityLib: FixidityLib.address,
        LogarithmLib: LogarithmLib.address,
        ExponentLib: ExponentLib.address,
        InterestRateModel: InterestRateModel.address,
        PriceOracles: PriceOracles.address,
        PoolPawn: PoolPawn.address
    };

    fs.writeFileSync(output, JSON.stringify(deployed, null, 4));
};