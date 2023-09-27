// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "../../../src/interfaces/external/IERC20.sol";
import {IUniswapV3Factory} from "../../../src/interfaces/external/uniswap-v3/core-v1.0.0/IUniswapV3Factory.sol";
import {ISwapRouter} from "../../../src/interfaces/external/uniswap-v3/periphery-v1.3.0/ISwapRouter.sol";
import {INonfungibleTokenPositionDescriptor} from "../../../src/interfaces/external/uniswap-v3/periphery-v1.3.0/INonfungibleTokenPositionDescriptor.sol";
import {INonfungiblePositionManager} from "../../../src/interfaces/external/uniswap-v3/periphery-v1.3.0/INonfungiblePositionManager.sol";
import {ERC20, ERC20Permit} from "@oz-v4.9.3/token/ERC20/extensions/ERC20Permit.sol";

string constant v3FactoryArtifact = "lib/compiled/uni-v3-core-v1.0.0/UniswapV3Factory.json";
string constant weth9Artifact = "lib/compiled/WETH9.json";
string constant swapRouterArtifact = "lib/compiled/uni-v3-periphery-v1.0.0/SwapRouter.json";
string constant nonFungibleTokenPositionDescriptorArtifact = "lib/compiled/uni-v3-periphery-v1.0.0/NonfungibleTokenPositionDescriptor.json";
string constant nonFungiblePositionManagerArtifact = "lib/compiled/uni-v3-periphery-v1.0.0/NonfungiblePositionManager.json";

interface IWETH9 is IERC20 {
    function deposit() external payable;
}

contract TestERC20 is ERC20Permit {
    constructor(uint256 amountToMint) ERC20("Test ERC20", "TEST") ERC20Permit("Test ERC20") {
        _mint(msg.sender, amountToMint);
    }
}

// Base fixture deploying V3 Factory, V3 Router and WETH9
contract V3RouterFixture is Test {
    IUniswapV3Factory public factory;
    IWETH9 public weth9;
    ISwapRouter public router;

    // Deploys WETH9 and V3 Core's Factory contract, and then
    // hooks them on the router
    function setUp() public virtual {
        address _weth9 = deployCode(weth9Artifact);
        weth9 = IWETH9(_weth9);

        address _factory = deployCode(v3FactoryArtifact);
        factory = IUniswapV3Factory(_factory);

        address _router = deployCode(swapRouterArtifact, abi.encode(_factory, _weth9));
        router = ISwapRouter(_router);
    }
}

// Fixture which deploys the 3 tokens we'll use in the tests and the NFT position manager
contract CompleteFixture is V3RouterFixture {
    TestERC20[] tokens;
    INonfungibleTokenPositionDescriptor nftDescriptor;
    INonfungiblePositionManager nft;

    function setUp() public virtual override {
        super.setUp();

        // deploy the 3 tokens
        address token0 = address(new TestERC20(type(uint256).max / 2));
        address token1 = address(new TestERC20(type(uint256).max / 2));
        address token2 = address(new TestERC20(type(uint256).max / 2));
        require(token0 < token1, "unexpected token ordering 1");
        require(token2 < token1, "unexpected token ordering 2");
        // pre-sorted manually, TODO do this properly
        tokens.push(TestERC20(token1));
        tokens.push(TestERC20(token2));
        tokens.push(TestERC20(token0));

        // we don't need to do the lib linking, forge deploys
        // all libraries and does it for us
        address _nftDescriptor = deployCode(nonFungibleTokenPositionDescriptorArtifact, abi.encode(address(tokens[0]), bytes32("ETH")));
        nftDescriptor = INonfungibleTokenPositionDescriptor(_nftDescriptor);

        address _nft = deployCode(nonFungiblePositionManagerArtifact, abi.encode(address(factory), address(weth9), address(nftDescriptor)));
        nft = INonfungiblePositionManager(_nft);
    }
}

// Final feature which sets up the user's balances & approvals
contract SwapRouterFixture is CompleteFixture {
    address wallet = vm.addr(1);
    address trader = vm.addr(2);

    struct Balances {
        uint256 weth9;
        uint256 token0;
        uint256 token1;
        uint256 token2;
    }

    function getBalances(address who) public view returns (Balances memory) {
        return Balances({weth9: weth9.balanceOf(who), token0: tokens[0].balanceOf(who), token1: tokens[1].balanceOf(who), token2: tokens[2].balanceOf(who)});
    }

    function setUp() public virtual override {
        super.setUp();

        vm.deal(trader, 100 ether);
        vm.deal(wallet, 100 ether);

        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].approve(address(router), type(uint256).max);
            tokens[i].approve(address(nft), type(uint256).max);
            vm.prank(trader);
            tokens[i].approve(address(router), type(uint256).max);
            tokens[i].transfer(trader, 1_000_000 * 1 ether);
        }
    }
}
