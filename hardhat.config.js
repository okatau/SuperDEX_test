require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.4.18",
      },
      {
        version: "0.5.16",
      },
      {
        version: "0.6.5",
      },
      {
        version: "0.6.12",
      },
      {
        version: "0.7.5",
      },
      {
        version: "0.8.10",
      }
    ],
    overrides: {
      "contracts/routers/NewUniswapV2ExchangeRouter/NewUniswapV2Router.sol": {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      "contracts/routers/SimpleSwap/SimpleSwap.sol": {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      "contracts/routers/MultiPath/MultiPath.sol": {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      "contracts/adapters/Adapter01.sol": {
        version: "0.7.5",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      "contracts/routers/ZeroxV4/Staking/Staking.sol": {
        version: "0.5.9",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        },
      },
      "contracts/routers/ZeroxV4/ZeroexExchangeProxy/features/NativeOrdersFeatureWOS.sol": {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        },
      },
    }
  }
};
