// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "@forge-std/Test.sol";
import {TestERC20} from "./mocks/TestERC20.sol";
import {IERC20} from "@oz-v4.9.3/token/ERC20/IERC20.sol";
import {IWETH9} from "@uni-v3-periphery/interfaces/external/IWETH9.sol";
import {UniswapV3Factory} from "@uni-v3-core/UniswapV3Factory.sol";
import {ISwapRouter} from "@uni-v3-periphery/interfaces/ISwapRouter.sol";
import {NonfungiblePositionManager} from "@uni-v3-periphery/NonfungiblePositionManager.sol";
import {INonfungiblePositionManager} from "@uni-v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {SwapRouter} from "@uni-v3-periphery/SwapRouter.sol";
import {TickMath} from "@uni-v3-core/libraries/TickMath.sol";
import {PoolAddress} from "@uni-v3-periphery/libraries/PoolAddress.sol";
import {console} from "forge-std/console.sol";

string constant weth9Artifact = "lib/common/weth/WETH9.json";

contract UniswapV3Math {
    uint256 constant PRECISION = 2 ** 96;

    uint24 constant FEE_MEDIUM = 3000;

    int24 constant TICK_LOW = 10;
    int24 constant TICK_MEDIUM = 60;

    // Computes the sqrt of the u64x96 fixed point price given the AMM reserves
    function encodePriceSqrt(uint256 reserve1, uint256 reserve0) public pure returns (uint160) {
        return uint160(sqrt((reserve1 * PRECISION * PRECISION) / reserve0));
    }

    // Fast sqrt, taken from Solmate.
    function sqrt(uint256 x) public pure returns (uint256 z) {
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

    function getMinTick(int24 tickSpacing) public pure returns (int24) {
        return (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
    }

    function getMaxTick(int24 tickSpacing) public pure returns (int24) {
        return (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
    }

    function getComputedPoolAddress(address tokenA, address tokenB, address factory) public pure returns (address) {
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        address token1 = tokenA < tokenB ? tokenB : tokenA;

        PoolAddress.PoolKey memory key = PoolAddress.PoolKey({token0: token0, token1: token1, fee: FEE_MEDIUM});

        return PoolAddress.computeAddress(factory, key);
    }

    function encodePath(address[] memory path, uint24[] memory fees) public pure returns (bytes memory) {
        bytes memory res;
        for (uint256 i = 0; i < fees.length; i++) {
            res = abi.encodePacked(res, path[i], fees[i]);
        }
        res = abi.encodePacked(res, path[path.length - 1]);
        return res;
    }
}

abstract contract WethDeployer is Test {
    function deployWeth() public returns (address) {
        return deployCode(weth9Artifact);
    }
}

abstract contract UniswapV3CoreDeployer is Test {
    function deployFactory() public returns (address) {
        return address(new UniswapV3Factory());
    }
}

abstract contract UniswapV3PeripheryDeployer is Test {
    function deployNonfungiblePositionManager(address factory, address weth, address nftDescriptor)
        public
        returns (address)
    {
        return address(new NonfungiblePositionManager(factory, weth, nftDescriptor));
    }

    function deploySwapRouter(address factory, address weth) public returns (address) {
        return address(new SwapRouter(factory, weth));
    }
}

abstract contract UniswapV3Deployer is Test, WethDeployer, UniswapV3CoreDeployer, UniswapV3PeripheryDeployer {
    function deployUniswapV3() public returns (address weth, address factory, address nftManager, address router) {
        weth = deployWeth();
        factory = deployFactory();
        nftManager = deployNonfungiblePositionManager(address(factory), address(weth), address(0));
        router = deploySwapRouter(address(factory), address(weth));
    }
}

abstract contract UniswapV3Utils is Test, UniswapV3Math {
    function createPool(address tokenA, address tokenB, address nftManager) public returns (address pool) {
        uint160 sqrtPriceForCreatePool = encodePriceSqrt(117_227_595_982_000, 137_200);
        //uint160 sqrtPriceForCreatePool = encodePriceSqrt(1, 1);

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        pool = NonfungiblePositionManager(payable(nftManager)).createAndInitializePoolIfNecessary(
            token0, token1, FEE_MEDIUM, sqrtPriceForCreatePool
        );
    }

    function mintLiquidity(address tokenA, address tokenB, uint256 spendAmount, address nftManager) public {
        (address _token0, address _token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: _token0,
            token1: _token1,
            fee: FEE_MEDIUM,
            tickLower: getMinTick(TICK_MEDIUM),
            tickUpper: getMaxTick(TICK_MEDIUM),
            amount0Desired: spendAmount,
            amount1Desired: spendAmount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: makeAddr("recycle-bin"),
            deadline: block.timestamp
        });

        NonfungiblePositionManager(payable(nftManager)).mint(params);
    }

    function doExactInputSwap(address tokenIn, address tokenOut, uint256 amountIn, address router, address _recipient)
        public
        returns (uint256 amountOut)
    {
        address[] memory _tokens = new address[](2);
        _tokens[0] = tokenIn;
        _tokens[1] = tokenOut;

        uint24[] memory _fees = new uint24[](1);
        _fees[0] = FEE_MEDIUM;

        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: encodePath(_tokens, _fees),
            recipient: _recipient,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        amountOut = ISwapRouter(router).exactInput(swapParams);
    }
}

abstract contract UniswapV3Mocks is Test, UniswapV3Utils, UniswapV3Deployer {
    struct UniAddresses {
        address tokenA;
        address tokenB;
        address weth;
        address pool_a_b;
        address pool_a_weth;
        address pool_b_weth;
        address factory;
        address router;
    }

    UniAddresses public mockUni;

    function setUp() public virtual {
        TestERC20 _tokenA = new TestERC20("MockToken A", "MCK-A", 6);
        TestERC20 _tokenB = new TestERC20("MockToken B", "MCK-B", 18);

        (address _weth, address _factory, address _nftManager, address _router) = deployUniswapV3();

        address _pool_a_b = createPool(address(_tokenA), address(_tokenB), _nftManager);
        address _pool_a_weth = createPool(address(_tokenA), address(_weth), _nftManager);
        address _pool_b_weth = createPool(address(_tokenB), address(_weth), _nftManager);

        TestERC20(_tokenA).mint(10_000_000 ether);
        TestERC20(_tokenB).mint(10_000_000 ether);

        _tokenA.approve(address(_nftManager), 10_000_000 ether);
        _tokenB.approve(address(_nftManager), 10_000_000 ether);
        _tokenA.approve(address(_router), 10_000_000 ether);
        _tokenB.approve(address(_router), 10_000_000 ether);

        IERC20(_weth).approve(address(_nftManager), 10_000_000 ether);
        IERC20(_weth).approve(address(_router), 10_000_000 ether);

        IWETH9(_weth).deposit{value: 10_000 ether}();

        mintLiquidity(address(_tokenA), address(_tokenB), 1000 ether, _nftManager);
        mintLiquidity(address(_tokenA), address(_weth), 1000 ether, _nftManager);
        mintLiquidity(address(_tokenB), address(_weth), 1000 ether, _nftManager);

        mockUni = UniAddresses({
            tokenA: address(_tokenA),
            tokenB: address(_tokenB),
            weth: address(_weth),
            pool_a_b: address(_pool_a_b),
            pool_a_weth: address(_pool_a_weth),
            pool_b_weth: address(_pool_b_weth),
            factory: address(_factory),
            router: address(_router)
        });

        vm.label(address(_tokenA), "MockTokenA");
        vm.label(address(_tokenB), "MockTokenB");
        vm.label(address(_weth), "MockWeth");
        vm.label(address(_pool_a_b), "Mock Pool AB");
        vm.label(address(_pool_a_weth), "Mock Pool AWETH");
        vm.label(address(_pool_b_weth), "Mock Pool BWETH");
        vm.label(address(_factory), "Mock Factory");
        vm.label(address(_router), "Mock Router");
    }
}
