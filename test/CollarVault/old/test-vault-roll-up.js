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
const maturityTimestampForTesting = 1670337500; // 
const mainneturl = process.env.MAINNET_RPC_URL + process.env.INFURA_API_KEY || "https://nowhere"
const laterTimestampForRolling = maturityTimestampForTesting+100*30*24*60*60; // roll it a month longer

const qtyToTest = "0.1" //will be parsethd
const dexToTest = deployConfig.addressbook.mainnet.uniswapRouterV3

// VAULT TESTS

describe("CollarVault and Roll", function () {
    let collarVault, owner, joe, mike, fee;
    this.beforeEach(async function (){ //gets you a brand new contract for each test 
        await network.provider.request({method: "hardhat_reset",params: [
            {forking: {jsonRpcUrl: mainneturl, blockNumber: 16270000}}
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
            1682192947, // future
            dexToTest, // dexrouter
            deployConfig.addressbook.mainnet.oracleEthUsd // oracle
        );
        //post trade details for prior trade
        await collarVault.connect(owner).postTradeDetailsA(
          99104088/2, //lent
          116599590/2, //fill
          11659960/2,//collat
          13991950/2,//proceeds
          deployConfig.addressbook.mainnet.weth
        )
        await collarVault.connect(owner).postTradeDetailsB(
          34979876/2,//fee
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
        await usdc.connect(whaleusdc).transfer(collarVault.address,11659960/2); //mikes collat
        await usdc.connect(whaleusdc).transfer(collarVault.address,13991950/2); //vaults proceeds
        await usdc.connect(whaleusdc).transfer(joe.address,99104088/2); //joes loan
        collarVault = await new ethers.Contract(collarVault.address,vaultabi);
        // await collarVault.connect(joe).setSettleType(0); // set to netsh
    })
    it("executeRoll - stock higher, physical", async function () {
        await collarVault.connect(joe).requestRollPrice(85,laterTimestampForRolling);
        await usdc.connect(joe).approve(collarVault.address,10000*1e6); //10k approved, 6dp
        await collarVault.connect(joe).setSettleType(2); // set to physical
        await collarVault.connect(joe).postPhysical({value: utils.parseEther("0.06")}); //
        await collarVault.connect(mike).showRollPrice(110);
        await collarVault.connect(joe).giveRollOrder();
        await usdc.connect(mike).approve(collarVault.address,10000*1e6); //10k approved, 6dp
        await collarVault.connect(mike).executeRoll();
        const vaultdeets = (await collarVault.connect(joe).getVaultDetails());
        assert.equal(vaultdeets[0].toString(),"100000000000000000"); // 0.1 eth qty (unch)
        assert.equal(vaultdeets[1].toString(),String(103320050)); // lent (unch) - 544$
        assert.equal(vaultdeets[3].toString(),String(88)); // putstrikepct (unch)
        assert.equal(vaultdeets[4].toString(),String(110)); // callstrikepct (unch)
        assert.equal(vaultdeets[5].toString(),laterTimestampForRolling); //new maturityTimestamp
        assert.equal(vaultdeets[6].toString(),"1215530000"); //filled vs oracle
        assert.equal(vaultdeets[7].toString(), "12155300"); //mmCollat 6dp - 10% on the new vault
        assert.equal(vaultdeets[8].toString(), "14586360"); //proceeds (100 to 88) to 6dp
        assert.equal(vaultdeets[11].toString(),"1"); //rollcount now +1!
    })
    it("executeRoll - stock higher, cash", async function () {
        await collarVault.connect(joe).requestRollPrice(85,laterTimestampForRolling);
        await usdc.connect(joe).approve(collarVault.address,10000*1e6); //10k approved, 6dp
        await collarVault.connect(joe).setSettleType(1); // set to cash
        await collarVault.connect(joe).postCash(100*1e6); // post that cash
        await collarVault.connect(mike).showRollPrice(110);
        await collarVault.connect(joe).giveRollOrder();
        await usdc.connect(mike).approve(collarVault.address,10000*1e6); //10k approved, 6dp
        await collarVault.connect(mike).executeRoll();
        const vaultdeets = (await collarVault.connect(joe).getVaultDetails());
        assert.equal(vaultdeets[0].toString(),"100000000000000000"); // 0.1 eth qty (unch)
        assert.equal(vaultdeets[1].toString(),String(103320050)); // lent (unch) - 544$
        assert.equal(vaultdeets[3].toString(),String(88)); // putstrikepct (unch)
        assert.equal(vaultdeets[4].toString(),String(110)); // callstrikepct (unch)
        assert.equal(vaultdeets[5].toString(),laterTimestampForRolling); //new maturityTimestamp
        assert.equal(vaultdeets[6].toString(),"1215530000"); //filled vs oracle
        assert.equal(vaultdeets[7].toString(), "12155300"); //mmCollat 6dp - 10% on the new vault
        assert.equal(vaultdeets[8].toString(), "14586360"); //proceeds (100 to 88) to 6dp
        assert.equal(vaultdeets[11].toString(),"1"); //rollcount now +1!
    })
})