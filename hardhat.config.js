require("@nomiclabs/hardhat-ethers");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.27",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    // Local development network
    hardhat: {
      chainId: 1337
    },
    localhost: {
      url: "http://127.0.0.1:8545"
    },
    
    // Sepolia testnet (for safe testing)
    sepolia: {
      url: `https://sepolia.infura.io/v3/${process.env.INFURA_API_KEY || 'your-infura-key'}`,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 11155111,
      gas: 2100000,
      gasPrice: 8000000000
    },
    
    // Ethereum mainnet (for production)
    mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY || 'your-infura-key'}`,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 1,
      gas: 2100000,
      gasPrice: 20000000000
    }
  }
};
