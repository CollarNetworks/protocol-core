// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "@forge-std/Test.sol";
import {TestERC20} from "./TestERC20.sol";
import {IERC20} from "@oz-v4.9.3/token/ERC20/IERC20.sol";
import {IWETH9} from "@uni-v3-periphery/interfaces/external/IWETH9.sol";
import {UniswapV3Factory} from "@uni-v3-core/UniswapV3Factory.sol";
import {ISwapRouter} from "@uni-v3-periphery/interfaces/ISwapRouter.sol";
import {NonfungiblePositionManager as NFTManager} from "@uni-v3-periphery/NonfungiblePositionManager.sol";
import {INonfungiblePositionManager} from "@uni-v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {SwapRouter} from "@uni-v3-periphery/SwapRouter.sol";
import {PoolAddress} from "@uni-v3-periphery/libraries/PoolAddress.sol";
import {console} from "@forge-std/console.sol";
import {MockWeth} from "./MockWeth.sol";
import {UniswapV3Math, UniswapV3Utils} from "../libs/UniswapV3Lib.sol";

//uint160 sqrtPriceForCreatePool = UniswapV3Math.encodePriceSqrt(117_227_595_982_000, 137_200);
//tokenA = address(new TestERC20("MockToken A", "MCK-A", 6));
//tokenB = address(new TestERC20("MockToken B", "MCK-B", 18));

contract UniswapV3Mocks is Test, UniswapV3Utils {
    address public tokenA;
    address public tokenB;
    address public weth;
    address public pool_a_b_med_fee;
    address public pool_a_weth_med_fee;
    address public pool_b_weth_med_fee;
    address public factory;
    address public router;
    address public nftManager;

    constructor() {
        createMocks();
        vm.label(address(this), "UniswapV3Mocks");
    }

    function createMocks() public virtual {
        (weth, factory, nftManager, router) = deployUniswapV3();

        tokenA = address(new TestERC20("MockToken A (6 Decimals)", "MCK-A-6DP", 6));
        tokenB = address(new TestERC20("MockToken B (18 Decimals)", "MCK-B-18DP", 18));

        vm.label(tokenA, "Mock Token A");
        vm.label(tokenB, "Mock Token B");
        vm.label(weth, "Mock Weth");
        vm.label(factory, "Mock Factory");
        vm.label(router, "Mock Router");

        pool_a_b_med_fee = setupMediumFeePool(tokenA, tokenB, 1000 ether, 1000 ether);
        pool_a_weth_med_fee = setupMediumFeePool(tokenA, weth, 1000 ether, 1 ether);
        pool_b_weth_med_fee = setupMediumFeePool(tokenB, weth, 1000 ether, 1 ether);

        vm.label(pool_a_b_med_fee, "Mock Pool A-B (Fee: Med)");
        vm.label(pool_a_weth_med_fee, "Mock Pool A-WETH (Fee: Med)");
        vm.label(pool_b_weth_med_fee, "Mock Pool B-WETH (Fee: Med)");
    }

    function setupLowFeePool(address _tokenA, address _tokenB, uint256 _reserveA, uint256 _reserveB) public returns (address) {
        return setupPool(_tokenA, _tokenB, _reserveA, _reserveB, UniswapV3Math.FEE_LOW);
    }

    function setupMediumFeePool(address _tokenA, address _tokenB, uint256 _reserveA, uint256 _reserveB) public returns (address) {
        return setupPool(_tokenA, _tokenB, _reserveA, _reserveB, UniswapV3Math.FEE_MEDIUM);
    }

    function setupHighFeePool(address _tokenA, address _tokenB, uint256 _reserveA, uint256 _reserveB) public returns (address) {
        return setupPool(_tokenA, _tokenB, _reserveA, _reserveB, UniswapV3Math.FEE_HIGH);
    }

    function setupLowFeeWethPool(address token, uint256 reserveToken, uint256 reserveWeth) public returns (address) {
        return setupPool(token, weth, reserveToken, reserveWeth, UniswapV3Math.FEE_LOW);
    }

    function setupMediumFeeWethPool(address _token, uint256 _reserveToken, uint256 _reserveWeth) public returns (address) {
        return setupPool(_token, weth, _reserveToken, _reserveWeth, UniswapV3Math.FEE_MEDIUM);
    }

    function setupHighFeeWethPool(address _token, uint256 _reserveToken, uint256 _reserveWeth) public returns (address) {
        return setupPool(_token, weth, _reserveToken, _reserveWeth, UniswapV3Math.FEE_HIGH);
    }

    function setupWethPool(address _token, uint256 _reserveToken, uint256 _reserveWeth, uint24 _fee) public returns (address) {
        return setupPool(_token, weth, _reserveToken, _reserveWeth, _fee);
    }

    function setupPool(address _tokenA, address _tokenB, uint256 _reserveA, uint256 _reserveB, uint24 _fee) public returns (address) {
        require(
            _fee == UniswapV3Math.FEE_LOW || _fee == UniswapV3Math.FEE_MEDIUM || _fee == UniswapV3Math.FEE_HIGH,
            "UniswapV3Mocks: invalid fee"
        );

        (address _token0, uint256 _reserve0, address _token1, uint256 _reserve1) =
            _tokenA < _tokenB ? (_tokenA, _reserveA, _tokenB, _reserveB) : (_tokenB, _reserveB, _tokenA, _reserveA);

        address pool = createPool(_token0, _reserve0, _token1, _reserve1, nftManager, _fee);

        vm.label(address(this), "UniswapV3Mocks");

        TestERC20(_token0).mint(_reserve0);
        TestERC20(_token1).mint(_reserve1);

        TestERC20(_token0).approve(nftManager, _reserve0);
        TestERC20(_token1).approve(nftManager, _reserve1);

        mintLiquidity(_token0, _token1, _reserve0, _reserve1, _fee, nftManager, msg.sender);

        return pool;
    }
}
