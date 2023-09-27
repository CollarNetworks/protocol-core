// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Test} from "@forge-std/Test.sol";
import {ERC20, ERC20Permit} from "@oz-v4.9.3/token/ERC20/extensions/ERC20Permit.sol";
import {UniswapV3Factory} from "@uni-v3-core/UniswapV3Factory.sol";
import {IWETH9} from "@uni-v3-periphery/interfaces/external/IWETH9.sol";
import {ISwapRouter} from "@uni-v3-periphery/interfaces/ISwapRouter.sol";
import {SwapRouter} from "@uni-v3-periphery/SwapRouter.sol";
import {NonfungibleTokenPositionDescriptor} from "@uni-v3-periphery/NonfungibleTokenPositionDescriptor.sol";
import {NonfungiblePositionManager} from "@uni-v3-periphery/NonfungiblePositionManager.sol";
import {INonfungibleTokenPositionDescriptor} from "@uni-v3-periphery/interfaces/INonfungibleTokenPositionDescriptor.sol";
import {INonfungiblePositionManager} from "@uni-v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {Tick} from "@uni-v3-core/libraries/Tick.sol";
import {TickMath} from "@uni-v3-core/libraries/TickMath.sol";
import {Path} from "@uni-v3-periphery/libraries/Path.sol";
import {PoolAddress} from "@uni-v3-periphery/libraries/PoolAddress.sol";

string constant weth9Artifact = "lib/common/weth/WETH9.json";
uint24 constant FEE_MEDIUM = 3000;
int24 constant TICK_LOW = 10;
int24 constant TICK_MEDIUM = 60;

// Fast sqrt, taken from Solmate.
function sqrt(uint256 x) pure returns (uint256 z) {
    assembly {
        // Start off with z at 1.
        z := 1

        // Used below to help find a nearby power of 2.
        let y := x

        // Find the lowest power of 2 that is at least sqrt(x).
        if iszero(lt(y, 0x100000000000000000000000000000000)) {
            y := shr(128, y) // Like dividing by 2 ** 128.
            z := shl(64, z) // Like multiplying by 2 ** 64.
        }
        if iszero(lt(y, 0x10000000000000000)) {
            y := shr(64, y) // Like dividing by 2 ** 64.
            z := shl(32, z) // Like multiplying by 2 ** 32.
        }
        if iszero(lt(y, 0x100000000)) {
            y := shr(32, y) // Like dividing by 2 ** 32.
            z := shl(16, z) // Like multiplying by 2 ** 16.
        }
        if iszero(lt(y, 0x10000)) {
            y := shr(16, y) // Like dividing by 2 ** 16.
            z := shl(8, z) // Like multiplying by 2 ** 8.
        }
        if iszero(lt(y, 0x100)) {
            y := shr(8, y) // Like dividing by 2 ** 8.
            z := shl(4, z) // Like multiplying by 2 ** 4.
        }
        if iszero(lt(y, 0x10)) {
            y := shr(4, y) // Like dividing by 2 ** 4.
            z := shl(2, z) // Like multiplying by 2 ** 2.
        }
        if iszero(lt(y, 0x8)) {
            // Equivalent to 2 ** z.
            z := shl(1, z)
        }

        // Shifting right by 1 is like dividing by 2.
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))

        // Compute a rounded down version of z.
        let zRoundDown := div(x, z)

        // If zRoundDown is smaller, use it.
        if lt(zRoundDown, z) { z := zRoundDown }
    }
}

uint256 constant PRECISION = 2 ** 96;

// Computes the sqrt of the u64x96 fixed point price given the AMM reserves
function encodePriceSqrt(uint256 reserve1, uint256 reserve0) pure returns (uint160) {
    return uint160(sqrt((reserve1 * PRECISION * PRECISION) / reserve0));
}

function getMinTick(int24 tickSpacing) pure returns (int24) {
    return (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
}

function getMaxTick(int24 tickSpacing) pure returns (int24) {
    return (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
}

function encodePath(address[] memory path, uint24[] memory fees) pure returns (bytes memory) {
    bytes memory res;
    for (uint256 i = 0; i < fees.length; i++) {
        res = abi.encodePacked(res, path[i], fees[i]);
    }
    res = abi.encodePacked(res, path[path.length - 1]);
    return res;
}

contract TestERC20 is ERC20Permit {
    constructor(uint256 amountToMint) ERC20("Test ERC20", "TEST") ERC20Permit("Test ERC20") {
        _mint(msg.sender, amountToMint);
    }
}
// Base fixture deploying V3 Factory, V3 Router and WETH9

contract V3RouterFixture is Test {
    UniswapV3Factory public factory;
    IWETH9 public weth9;
    SwapRouter public router;

    // Deploys WETH9 and V3 Core's Factory contract, and then
    // hooks them on the router
    function setUp() public virtual {
        address _weth9 = deployCode(weth9Artifact);
        weth9 = IWETH9(_weth9);

        factory = new UniswapV3Factory();

        router = new SwapRouter(address(factory), address(weth9));
    }
}

// Fixture which deploys the 3 tokens we'll use in the tests and the NFT position manager
contract CompleteFixture is V3RouterFixture {
    TestERC20[] tokens;
    NonfungibleTokenPositionDescriptor nftDescriptor;
    NonfungiblePositionManager nft;

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
        nftDescriptor = new NonfungibleTokenPositionDescriptor(address(tokens[0]), bytes32("ETH"));
        nft = new NonfungiblePositionManager(address(factory), address(weth9), address(nftDescriptor));
    }
}

// Final feature which sets up the user's balances & approvals
contract SwapRouterFixture is CompleteFixture {
    address immutable wallet = vm.addr(1);
    address immutable trader = vm.addr(2);

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

contract Swaps is SwapRouterFixture {
    function setUp() public override {
        super.setUp();

        createPool(address(tokens[0]), address(tokens[1]));
        createPool(address(tokens[1]), address(tokens[2]));
    }

    uint160 immutable sqrtPriceForCreatePool = encodePriceSqrt(1, 1);
    int24 immutable minMediumTick = getMinTick(TICK_MEDIUM);
    int24 immutable maxMediumTick = getMaxTick(TICK_MEDIUM);

    function createPool(address tokenAddressA, address tokenAddressB) public {
        if (tokenAddressA > tokenAddressB) {
            address tmp = tokenAddressA;
            tokenAddressA = tokenAddressB;
            tokenAddressB = tmp;
        }

        nft.createAndInitializePoolIfNecessary(tokenAddressA, tokenAddressB, FEE_MEDIUM, sqrtPriceForCreatePool);

        INonfungiblePositionManager.MintParams memory liquidityParams = INonfungiblePositionManager.MintParams({
            token0: tokenAddressA,
            token1: tokenAddressB,
            fee: FEE_MEDIUM,
            tickLower: minMediumTick,
            tickUpper: maxMediumTick,
            recipient: wallet,
            amount0Desired: 1_000_000,
            amount1Desired: 1_000_000,
            amount0Min: 0,
            amount1Min: 0,
            deadline: 1
        });

        nft.mint(liquidityParams);
    }
}

contract ExactInput is Swaps {
    function exactInput(address[] memory tokens, uint256 amountIn, uint256 amountOutMinimum) public {
        vm.startPrank(trader);

        bool inputIsWETH = tokens[0] == address(weth9);
        bool outputIsWETH = tokens[tokens.length - 1] == address(weth9);
        uint256 value = inputIsWETH ? amountIn : 0;

        uint24[] memory fees = new uint24[](tokens.length - 1);
        for (uint256 i = 0; i < fees.length; i++) {
            fees[i] = FEE_MEDIUM;
        }

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: encodePath(tokens, fees),
            recipient: outputIsWETH ? address(0) : trader,
            deadline: 1,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        bytes[] memory data;
        bytes memory inputs = abi.encodeWithSelector(router.exactInput.selector, params);
        if (outputIsWETH) {
            data = new bytes[](2);
            data[0] = inputs;
            data[1] = abi.encodeWithSelector(router.unwrapWETH9.selector, amountOutMinimum, trader);
        }

        // ensure that the swap fails if the limit is any higher
        params.amountOutMinimum += 1;
        vm.expectRevert(bytes("Too little received"));
        router.exactInput{value: value}(params);
        params.amountOutMinimum -= 1;

        if (outputIsWETH) {
            router.multicall{value: value}(data);
        } else {
            router.exactInput{value: value}(params);
        }

        vm.stopPrank();
    }
}

contract SinglePool is ExactInput {
    function testZeroToOne() public {
        address pool = factory.getPool(address(tokens[0]), address(tokens[1]), FEE_MEDIUM);

        Balances memory poolBefore = getBalances(pool);
        Balances memory traderBefore = getBalances(trader);

        address[] memory _tokens = new address[](2);
        _tokens[0] = address(tokens[0]);
        _tokens[1] = address(tokens[1]);
        exactInput(_tokens, 3, 1);

        Balances memory poolAfter = getBalances(pool);
        Balances memory traderAfter = getBalances(trader);
        require(traderAfter.token0 == traderBefore.token0 - 3);
        require(traderAfter.token1 == traderBefore.token1 + 1);
        require(poolAfter.token0 == poolBefore.token0 + 3);
        require(poolAfter.token1 == poolBefore.token1 - 1);
    }

    function testOneToZero() public {
        address pool = factory.getPool(address(tokens[1]), address(tokens[0]), FEE_MEDIUM);

        Balances memory poolBefore = getBalances(pool);
        Balances memory traderBefore = getBalances(trader);

        address[] memory _tokens = new address[](2);
        _tokens[0] = address(tokens[1]);
        _tokens[1] = address(tokens[0]);
        exactInput(_tokens, 3, 1);

        Balances memory poolAfter = getBalances(pool);
        Balances memory traderAfter = getBalances(trader);
        require(traderAfter.token0 == traderBefore.token0 + 1);
        require(traderAfter.token1 == traderBefore.token1 - 3);
        require(poolAfter.token0 == poolBefore.token0 - 1);
        require(poolAfter.token1 == poolBefore.token1 + 3);
    }
}

contract MultiPool is ExactInput {
    function testZeroToOneToTwo() public {
        Balances memory traderBefore = getBalances(trader);

        address[] memory _tokens = new address[](3);
        _tokens[0] = address(tokens[0]);
        _tokens[1] = address(tokens[1]);
        _tokens[2] = address(tokens[2]);
        exactInput(_tokens, 5, 1);

        Balances memory traderAfter = getBalances(trader);
        require(traderAfter.token0 == traderBefore.token0 - 5);
        require(traderAfter.token2 == traderBefore.token2 + 1);
    }

    function testTwoToOneToZero() public {
        Balances memory traderBefore = getBalances(trader);

        address[] memory _tokens = new address[](3);
        _tokens[0] = address(tokens[2]);
        _tokens[1] = address(tokens[1]);
        _tokens[2] = address(tokens[0]);
        exactInput(_tokens, 5, 1);

        Balances memory traderAfter = getBalances(trader);
        require(traderAfter.token2 == traderBefore.token2 - 5);
        require(traderAfter.token0 == traderBefore.token0 + 1);
    }

    event Transfer(address indexed from, address indexed to, uint256 amount);

    function testEvents() public {
        address[] memory _tokens = new address[](3);
        _tokens[0] = address(tokens[0]);
        _tokens[1] = address(tokens[1]);
        _tokens[2] = address(tokens[2]);

        PoolAddress.PoolKey memory key;
        address addr;

        // Events get emitted in the following order:
        // 1. Pool0 -> Router
        // 2. Trader -> Pool0
        // 3. Pool1 -> Trader
        // 4. Router -> Pool1

        vm.expectEmit(true, true, true, true);
        key = PoolAddress.PoolKey(address(tokens[1]), address(tokens[0]), FEE_MEDIUM);
        addr = PoolAddress.computeAddress(address(factory), key);
        emit Transfer(addr, address(router), 3);

        vm.expectEmit(true, true, true, true);
        key = PoolAddress.PoolKey(address(tokens[1]), address(tokens[0]), FEE_MEDIUM);
        addr = PoolAddress.computeAddress(address(factory), key);
        emit Transfer(trader, addr, 5);

        vm.expectEmit(true, true, true, true);
        key = PoolAddress.PoolKey(address(tokens[1]), address(tokens[2]), FEE_MEDIUM);
        addr = PoolAddress.computeAddress(address(factory), key);
        emit Transfer(addr, trader, 1);

        vm.expectEmit(true, true, true, true);
        key = PoolAddress.PoolKey(address(tokens[1]), address(tokens[2]), FEE_MEDIUM);
        addr = PoolAddress.computeAddress(address(factory), key);
        emit Transfer(address(router), addr, 3);

        exactInput(_tokens, 5, 1);
    }
}
