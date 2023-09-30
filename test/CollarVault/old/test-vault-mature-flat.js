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
const maturityTimestampForTesting = 1670337200; // 
const mainneturl = process.env.MAINNET_RPC_URL + process.env.INFURA_API_KEY || "https://nowhere"
const dexToTest = deployConfig.addressbook.mainnet.uniswapRouterV3

describe("CollarVault Mature Flat", function () {
    let collarVault, owner, joe, mike, fee;
    this.beforeEach(async function (){ //gets you a brand new contract for each test 
        await network.provider.request({method: "hardhat_reset",params: [
            {forking: {jsonRpcUrl: mainneturl, blockNumber: 16126391}}
        ]});
        usdc = await new ethers.Contract(deployConfig.addressbook.mainnet.usdc,erc20abi);
        collarVaultFactory = await ethers.getContractFactory("CollarVault");
        [owner,joe,mike,fee] = await ethers.getSigners(); //joe=hnw,mm=mike,hack=zeke,fee=wallet
        //deploy mock vault w maturity of yday
        collarVault = await collarVaultFactory.deploy(
            owner.address, //admin
            0, //rfqid
            utils.parseEther("1"), // qty
            deployConfig.addressbook.mainnet.usdc, // lendAsset
            88, //putstrike
            110, //callstrike
            maturityTimestampForTesting, // day before
            dexToTest, // dexrouter
            deployConfig.addressbook.mainnet.oracleEthUsd // oracle
        );
        //post trade details for prior trade
        await collarVault.connect(owner).postTradeDetailsA(
          991040872, //lent
          1165995893, //fill
          116599590,//collat
          139919507,//proceeds
          deployConfig.addressbook.mainnet.weth
        )
        await collarVault.connect(owner).postTradeDetailsB(
          34979876,//fee
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
        await usdc.connect(whaleusdc).transfer(collarVault.address,116599590); //mikes collat
        await usdc.connect(whaleusdc).transfer(collarVault.address,139919507); //vaults proceeds
        await usdc.connect(whaleusdc).transfer(joe.address,991096509); //joes loan
        collarVault = await new ethers.Contract(collarVault.address,vaultabi);
    })
    // //BTWN CASES - mm and client split dollars, paid in cash or eth to client, mm always cash
    it("general maturity check - should be matured with updated oracle price / block timestamp / amt in it", async function () {
      assert.equal((await hre.ethers.provider.getBlock("latest")).timestamp,1670337403); //future time
      assert.equal((await collarVault.connect(owner).getOraclePriceExternal()).toString(),"1253604352650000000000"); //newpx
      assert.equal(await collarVault.connect(joe).checkMatured(),true);
      assert.equal((await usdc.connect(owner).balanceOf(collarVault.address)).toString(),"256519097"); //collat+proceeds, width of strikes
    })
    it("matureVault - netsh|phys, no repay, btwn - should pay some eth", async function () {
      await collarVault.connect(joe).setSettleType(2); //set to physical
      await collarVault.connect(mike).matureVault(); //only trades delta
      assert.equal((await usdc.connect(mike).balanceOf(mike.address)).toString(),"1000028991130"); //got back leftover collat
      assert.isAtLeast((await ethers.provider.getBalance(joe.address))/1e9,10000180220000);//joe should have ~0.18 more eth! needed to lop off zeroes
      //should be getting back some physical eth, all of it
    })
  })