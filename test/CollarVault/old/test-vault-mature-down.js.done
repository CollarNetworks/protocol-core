const fs = require('fs');
const {ethers} = require("hardhat");
const hre = require("hardhat");
const {assert} = require("chai");
const {utils} = require("ethers");
require('solidity-coverage');
require('dotenv').config();
const vaultabi = JSON.parse(fs.readFileSync("artifacts/contracts/CollarVault.sol/CollarVault.json")).abi;
const erc20abi = JSON.parse(fs.readFileSync("artifacts/@openzeppelin/contracts/token/ERC20/IERC20.sol/IERC20.json")).abi;
const deployConfig = JSON.parse(fs.readFileSync("deployconfig.json"));
const mainneturl = process.env.MAINNET_RPC_URL + process.env.INFURA_API_KEY || "https://nowhere"
const qtyToTest = "0.1" //will be parsethd
const dexToTest = deployConfig.addressbook.mainnet.uniswapRouterV3

describe("CollarVault Mature Down", function () {
    let collarVault, owner, joe, mike, fee;
    this.beforeEach(async function (){ //gets you a brand new contract for each test 
        await network.provider.request({method: "hardhat_reset",params: [
            {forking: {jsonRpcUrl: mainneturl, blockNumber: 16277284}}
        ]});
        usdc = await new ethers.Contract(deployConfig.addressbook.mainnet.usdc,erc20abi);
        collarVaultFactory = await ethers.getContractFactory("CollarVault");
        [owner,joe,mike,fee] = await ethers.getSigners(); //joe=hnw,mm=mike,hack=zeke,fee=wallet
        //deploy mock vault w maturity of yday
        collarVault = await collarVaultFactory.deploy(
            owner.address, //admin
            0, //rfqid
            utils.parseEther(qtyToTest), // qty
            deployConfig.addressbook.mainnet.usdc, // lendAsset
            88, //putstrike
            110, //callstrike
            1672058635, //  dec 27 ish - 100k seconds ~day
            dexToTest, // dexrouter
            deployConfig.addressbook.mainnet.oracleEthUsd
        );
        //post trade details for prior trade
        await collarVault.connect(owner).postTradeDetailsA(
          991040872*2, //lent
          1165995893*2, //fill
          116599590*2,//collat
          139919507*2,//proceeds
          deployConfig.addressbook.mainnet.weth
        )
        await collarVault.connect(owner).postTradeDetailsB(
          34979876*2,//fee
          fee.address,//feewallet
          3,//feerate
          mike.address,//mm
          joe.address//client
        )
        const usdcWhale = '0xf977814e90da44bfa03b6295a0616a897441acec'; //has like 600mm+lots of eth
        await hre.network.provider.request({method: "hardhat_impersonateAccount",params: [usdcWhale]});
        whaleusdc = await ethers.getSigner(usdcWhale);
        await usdc.connect(whaleusdc).transfer(joe.address,1000000*1e6); //joe stack
        await usdc.connect(whaleusdc).transfer(mike.address,1000000*1e6); //mike stack
        await usdc.connect(whaleusdc).transfer(collarVault.address,116599590*2); //mikes collat
        await usdc.connect(whaleusdc).transfer(collarVault.address,139919507*2); //vaults proceeds
        await usdc.connect(whaleusdc).transfer(joe.address,991096509*2); //joes loan
        collarVault = await new ethers.Contract(collarVault.address,vaultabi);
    })
    it("matureVault - new", async function () {
      await collarVault.connect(mike).matureVault(); //only trades delta
      assert.equal((await usdc.connect(mike).balanceOf(mike.address)).toString(),"1000051303819"); //mike makes $513 
      assert.equal((await ethers.provider.getBalance(joe.address)).toString(),"10000000000000000000000");//joe should make no more
      //should be getting back some physical eth, all of it
    })
  })
  