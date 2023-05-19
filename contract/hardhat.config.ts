import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter"
import "@nomiclabs/hardhat-web3";
import "@nomicfoundation/hardhat-verify";
const dotenv = require("dotenv");
dotenv.config({path: __dirname + '/.env'});
const { ETHERSCAN_API_KEY, METAMASK_API_KEY, SEPOLIA_ALCHEMY_API_URL, REPORT_GAS } = process.env;

const config: HardhatUserConfig = {
  defaultNetwork: "sepolia",
  solidity: "0.8.19",
  etherscan: {
    apiKey: ETHERSCAN_API_KEY,
  },
  networks: {
    sepolia: {
      url: SEPOLIA_ALCHEMY_API_URL,
      accounts: [`0x${METAMASK_API_KEY}`]
    }
  },
  gasReporter: {
    enabled: REPORT_GAS ? true : false
  },
};

export default config;
