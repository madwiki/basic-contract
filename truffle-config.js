const HDWalletProvider = require('truffle-hdwallet-provider');
const MNEMONIC = process.env.MNEMONIC;
const XDAI_HTTP = process.env.XDAI_HTTP;
const SOKOL_HTTP = process.env.SOKOL_HTTP;
const GAS_LIMIT = 7000000;

module.exports = {
  // Uncommenting the defaults below
  // provides for an easier quick-start with Ganache.
  // You can also follow this format for other networks;
  // see <http://truffleframework.com/docs/advanced/configuration>
  // for more details on how to specify configuration options!

  networks: {
    xdai: {
      network_id: 100,
      provider: () => new HDWalletProvider(MNEMONIC, XDAI_HTTP),
      gas: GAS_LIMIT,
      gasPrice: 10000000000,
    },
    sokol: {
      network_id: 77,
      provider: () => new HDWalletProvider(MNEMONIC, SOKOL_HTTP),
      gas: GAS_LIMIT,
      gasPrice: 10000000000,
    },
  },
  compilers: {
    solc: {
      settings: {
        optimizer: {
          enabled: true,
          runs: 200, // Optimize for how many times you intend to run the code
        },
      },
    },
  },
};
