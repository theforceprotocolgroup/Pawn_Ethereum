const HDWalletProvider = require('truffle-hdwallet-provider'); // eslint-disable-line
const path = require('path');

const sources = path.join(process.cwd(), 'contract');

module.exports = {
  compilers: {
    solc: {
      version: '0.5.13',
      parser: 'solcjs',
      settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        },
        //evmVersion: 'byzantium',
        evmVersion: 'istanbul',
      },
    },
  },
  contracts_directory: sources,
  networks: {
    // mainnet: {
    //   network_id: '1',
    //   provider: () => new HDWalletProvider(
    //     process.env.DEPLOYER_PRIVATE_KEY,
    //     'https://...'
    //   ),
    //   gasPrice: Number(process.env.GAS_PRICE),
    //   gas: 6900000,
    //   from: process.env.DEPLOYER_ACCOUNT,
    //   timeoutBlocks: 500,
    // },
    rinkeby: {
      network_id: '4',
      provider: () => new HDWalletProvider(
        process.env.DEPLOYER_PRIVATE_KEY,
        'https://rinkeby.infura.io/v3/3988726e52214208a238061b6200c65f'
      ),
      gasPrice: 10000000000, // 10 gwei
      gas: 9500000,
      timeoutBlocks: 1000,
    },
    ropsten: {
      network_id: '3',
      provider: () => new HDWalletProvider(
        process.env.DEPLOYER_PRIVATE_KEY,
        'https://ropsten.infura.io/v3/3988726e52214208a238061b6200c65f'
      ),
      gasPrice: 10000000000, // 10 gwei
      gas: 7500000,
      timeoutBlocks: 1000,
    },
  },
  plugins: [
    'truffle-plugin-verify'
  ],
  api_keys: {
      etherscan: process.env.ETHERSCAN_API_KEY
  },
};
