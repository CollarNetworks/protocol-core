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
const laterTimestampForRolling = maturityTimestampForTesting+30*24*60*60; // roll it a month longer

const qtyToTest = "0.1" //will be parsethd
const dexToTest = deployConfig.addressbook.mainnet.uniswapRouterV3

// VAULT TESTS

describe("CollarVault and Roll", function () {
    let collarEngine, collarVault, owner, joe, mike, fee, zeke;
    this.beforeEach(async function (){ //gets you a brand new contract for each test
        const usdcWhale = '0xf977814e90da44bfa03b6295a0616a897441acec'; //has like 600mm+lots of eth
        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [usdcWhale],
        });
        whaleusdc = await ethers.getSigner(usdcWhale);
        await usdc.connect(whaleusdc).transfer(joe.address,1000000*1e6); //1mm, 6dp
        await usdc.connect(whaleusdc).transfer(mike.address,1000000*1e6); //1mm, 6dp
        await collarEngine.connect(joe).requestPrice(utils.parseEther(qtyToTest),85,maturityTimestampForTesting,"");
        await collarEngine.connect(mike).ackPrice(joe.address);
        await collarEngine.connect(mike).showPrice(joe.address,110);
        await collarEngine.connect(joe).clientGiveOrder({value: utils.parseEther(qtyToTest)});
        await usdc.connect(mike).approve(collarEngine.address,10000*1e6);
        await collarEngine.connect(mike).executeTrade(joe.address);
        const vaultaddress = await collarEngine.getLastTradeVault(joe.address);
        collarVault = await new ethers.Contract(vaultaddress,vaultabi);
    })
    it("overall money/eth - make sure joe got loan, vault got collat!", async function () {
      assert.isAtLeast((await usdc.connect(joe).balanceOf(collarVault.address)).toNumber(),25656733); //should have at least mmcollat + proceeds    
      assert.equal((await ethers.provider.getBalance(collarVault.address)).toString(), "0"); //should have no eth
    })
    it("setSettleType - should allow you to flip it", async function () {
      assert.equal((await collarVault.connect(joe).checkSettleType()).toString(),0);
      await collarVault.connect(joe).setSettleType(1);
      assert.equal((await collarVault.connect(joe).checkSettleType()).toString(),1);
    })
    it("setRollPref - should allow you to flip it", async function () {
      assert.equal((await collarVault.connect(joe).checkRollType()),true);
      await collarVault.connect(joe).setRollPref(false);
      assert.equal((await collarVault.connect(joe).checkRollType()),false);
    })
    it("getVaultDetails - should pull trade details from the vault", async function () {
      var deets = await collarVault.connect(owner).getVaultDetails();
      assert.equal(deets[0].toString(),"100000000000000000");//qty 0.1 eth
      assert.isAtLeast(deets[1],99100000);//lent >=$991
      assert.isAtMost(deets[1],99200000);//lent >=$991
      assert.equal(deets[2],deployConfig.addressbook.mainnet.usdc);//right usdc
      assert.equal(deets[3].toString(),"88"); assert.equal(deets[4].toString(),"110");//right strikes
      assert.equal(deets[5].toString(),maturityTimestampForTesting);//maturity of 1apr24 as reqd
      assert.isAtLeast(deets[6],1166700000);//fill to 6dp
      assert.isAtMost(deets[6],1166800000);//fill to 6dp
      assert.isAtLeast(deets[7],11667000);//mmCollateral to 6dp
      assert.isAtMost(deets[7],11668000);//mmCollateral to 6dp
      assert.isAtLeast(deets[8],14000000);//proceeds (100 to 88) to 6dp
      assert.isAtMost(deets[8],14010000);//mmCollateral to 6dp
      assert.equal(deets[9],collarEngine.address);//engine
      assert.equal(deets[10].toString(),"0");//rfqid
    })
    it("repayLoan - should accept usdc in from client, flip bool", async function () {
      await usdc.connect(joe).approve(collarVault.address,10000*1e6);
      const joebefore = (await usdc.connect(joe).balanceOf(joe.address)).toNumber(); 
      const vaultbefore = (await usdc.connect(joe).balanceOf(collarVault.address)).toNumber(); 
      assert.equal(await collarVault.connect(joe).checkRepaid(),false);//not yet repaid
      await collarVault.connect(joe).repayLoan();
      const vaultafter = (await usdc.connect(joe).balanceOf(collarVault.address)).toNumber(); 
      const joeafter = (await usdc.connect(joe).balanceOf(joe.address)).toNumber(); 
      assert.equal(await collarVault.connect(joe).checkRepaid(),true);//now its repaid!
      assert.equal(joebefore-joeafter,vaultafter-vaultbefore);
      assert.isAtLeast(vaultafter-vaultbefore,102600000); //shd repay 88% of fill
      assert.isAtMost(vaultafter-vaultbefore,102700000); //shd repay 88% of fill
    })
    it("postPhysical - should accept ETH, update client collat", async function () {
      await collarVault.connect(joe).postPhysical({value: utils.parseEther("0.1")});
      const collatposted = (await collarVault.connect(joe).checkPhysicalCollateralPosted()).toString()
      assert.equal(collatposted,"100000000000000000");
    })
    it("reclaimPhysical - should reclaim ETH, update client collat", async function () {
      await collarVault.connect(joe).postPhysical({value: utils.parseEther("0.1")});
      await collarVault.connect(joe).reclaimPhysical(utils.parseEther("0.05"));
      const collatposted = (await collarVault.connect(joe).checkPhysicalCollateralPosted()).toString()
      assert.equal(collatposted,"50000000000000000");
    })
    /////////ROLLTESTS//////////////
    it("requestRollPrice - should request to roll", async function () {
      await collarVault.connect(joe).requestRollPrice(80,laterTimestampForRolling);
      const rolldeets = (await collarVault.connect(joe).getRollDetails());
      assert.equal(rolldeets[1].toString(),"1");
      assert.equal(rolldeets[2].toString(),"83");
      assert.equal(rolldeets[4].toString(),String(laterTimestampForRolling));
    })
    it("pullRollRequest - should pull roll request ", async function () {
      await collarVault.connect(joe).requestRollPrice(80,laterTimestampForRolling);
      await collarVault.connect(joe).pullRollRequest();
      const rolldeets = (await collarVault.connect(joe).getRollDetails());
      assert.equal(rolldeets[1].toString(),"0");
      assert.equal(rolldeets[2].toString(),"0");
      assert.equal(rolldeets[3].toString(),"0");
      assert.equal(rolldeets[4].toString(),"0");
    })
    it("testing showRollPrice - should show roll price ", async function () {
      await collarVault.connect(joe).requestRollPrice(80,laterTimestampForRolling);
    })
    it("showRollPrice - should show roll price ", async function () {
      await collarVault.connect(joe).requestRollPrice(80,laterTimestampForRolling);
      await collarVault.connect(mike).showRollPrice(109);
      const rolldeets = (await collarVault.connect(joe).getRollDetails());
      assert.equal(rolldeets[1].toString(),"2");
      assert.equal(rolldeets[3].toString(),"109");
    })
    it("giveRollOrder - should give roll order ", async function () {
      await collarVault.connect(joe).requestRollPrice(80,laterTimestampForRolling);
      await collarVault.connect(mike).showRollPrice(109);
      await collarVault.connect(mike).showRollPrice(110); // tests updating px as well
      await collarVault.connect(joe).giveRollOrder();
      const rolldeets = (await collarVault.connect(joe).getRollDetails());
      assert.equal(rolldeets[1].toString(),"3");
    })
    it("rejectRoll - should allow mm to reject order ", async function () {
      await collarVault.connect(joe).requestRollPrice(80,laterTimestampForRolling);
      await collarVault.connect(mike).showRollPrice(109);
      await collarVault.connect(joe).giveRollOrder();
      await collarVault.connect(mike).rejectRoll();
      const rolldeets = (await collarVault.connect(joe).getRollDetails());
      assert.equal(rolldeets[1].toString(),"0");
      assert.equal(rolldeets[2].toString(),"0");
      assert.equal(rolldeets[3].toString(),"0");
      assert.equal(rolldeets[4].toString(),"0");
    })
    //rolled immediately after using same oracle price
    it("executeRoll - vault status - immediate / cash - should unlock value, extend, same terms", async function () {
      await collarVault.connect(joe).setSettleType(1); // set to cash
      await collarVault.connect(joe).requestRollPrice(85,laterTimestampForRolling);
      await usdc.connect(joe).approve(collarVault.address,10000*1e6); //10k approved, 6dp
      await collarVault.connect(joe).postCash(100*1e6); //post fee worth
      await collarVault.connect(mike).showRollPrice(110);
      await collarVault.connect(joe).giveRollOrder();
      await usdc.connect(mike).approve(collarVault.address,10000*1e6); //10k approved, 6dp
      await collarVault.connect(mike).executeRoll();
      const vaultdeets = (await collarVault.connect(joe).getVaultDetails());
      assert.equal(vaultdeets[0].toString(),"100000000000000000"); // 0.1 eth qty (unch)
      assert.equal(vaultdeets[1].toString(),String(99643456)); // lent (unch)
      assert.equal(vaultdeets[3].toString(),String(88)); // putstrikepct (unch)
      assert.equal(vaultdeets[4].toString(),String(110)); // putstrikepct (unch)
      assert.equal(vaultdeets[5].toString(),laterTimestampForRolling); //new maturityTimestamp
      assert.equal(vaultdeets[6].toString(),"1172275959"); //fill (unch)
      assert.equal(vaultdeets[7].toString(), "11722759"); //mmCollat 6dp
      assert.equal(vaultdeets[8].toString(), "14067311"); //proceeds (100 to 88) to 6dp
      assert.equal(vaultdeets[11].toString(),"1"); //rollcount now +1!
    })
    it("executeRoll - user gain/loss check - immediate / cash", async function () {
      const vaultpre = (await usdc.connect(mike).balanceOf(collarVault.address)).toString()
      const mikepre = (await usdc.connect(mike).balanceOf(mike.address)).toString()
      const joepre = (await usdc.connect(mike).balanceOf(joe.address)).toString()
      const feepre = (await usdc.connect(mike).balanceOf(fee.address)).toString()
      await collarVault.connect(joe).requestRollPrice(85,laterTimestampForRolling);
      await usdc.connect(joe).approve(collarVault.address,10000*1e6); //10k approved, 6dp
      await collarVault.connect(joe).setSettleType(1); // set to cash
      await collarVault.connect(joe).postCash(5*1e6); //post collateral (slight bit for fee)
      await collarVault.connect(mike).showRollPrice(110);
      await collarVault.connect(joe).giveRollOrder();
      await usdc.connect(mike).approve(collarVault.address,10000*1e6); //10k approved, 6dp
      await collarVault.connect(mike).executeRoll();
      await collarVault.connect(joe).reclaimCash(await collarVault.connect(joe).getClaimableClientCash());
      const vaultpost = (await usdc.connect(mike).balanceOf(collarVault.address)).toString()
      const mikepost = (await usdc.connect(mike).balanceOf(mike.address)).toString()
      const joepost = (await usdc.connect(mike).balanceOf(joe.address)).toString()
      const feepost = (await usdc.connect(mike).balanceOf(fee.address)).toString()
      
      assert.isAtLeast(vaultpost-vaultpre,122500) // vault increases in net collat slightly
      assert.isAtMost(vaultpost-vaultpre,122600) // vault increases in net collat slightly
      assert.isAtLeast(mikepost-mikepre,-613000) // posting slightly more collateral, larger notl
      assert.isAtMost(mikepost-mikepre,-612000) // posting slightly more collateral, larger notl
      assert.isAtLeast(joepost-joepre,-3027000) // paid fee but got a bit back on roll
      assert.isAtMost(joepost-joepre,-3026000) // paid fee but got a bit back on roll
      assert.isAtLeast(feepost-feepre,3516000) // made fee!
      assert.isAtMost(feepost-feepre,3517000) // made fee!
      //const vaultdeets = (await collarVault.connect(joe).getVaultDetails());
      //rolling a vault filled at 1165 to 1172 insta roll vs the oracle -- is that an issue? mm wd show px
    })
    it("executeRoll - physical test", async function () {
      await collarVault.connect(joe).requestRollPrice(85,laterTimestampForRolling);
      await usdc.connect(joe).approve(collarVault.address,10000*1e6); //10k approved, 6dp
      await collarVault.connect(joe).setSettleType(2); // set to physical
      await collarVault.connect(joe).postPhysical({value: utils.parseEther("0.02")}); //post fee worth
      await collarVault.connect(mike).showRollPrice(110);
      await collarVault.connect(joe).giveRollOrder();
      await usdc.connect(mike).approve(collarVault.address,10000*1e6); //10k approved, 6dp
      await collarVault.connect(mike).executeRoll();
      const vaultdeets = (await collarVault.connect(joe).getVaultDetails());
      assert.equal(vaultdeets[0].toString(),"100000000000000000"); // 0.1 eth qty (unch)
      assert.equal(vaultdeets[1].toString(),String(99643456)); // lent (unch)
      assert.equal(vaultdeets[3].toString(),String(88)); // putstrikepct (unch)
      assert.equal(vaultdeets[4].toString(),String(110)); // putstrikepct (unch)
      assert.equal(vaultdeets[5].toString(),laterTimestampForRolling); //new maturityTimestamp
      assert.equal(vaultdeets[6].toString(),"1172275959"); //fill (unch)
      assert.equal(vaultdeets[7].toString(), "11722759"); //mmCollat 6dp
      assert.equal(vaultdeets[8].toString(), "14067311"); //proceeds (100 to 88) to 6dp
      assert.equal(vaultdeets[11].toString(),"1"); //rollcount now +1!
    })
  })