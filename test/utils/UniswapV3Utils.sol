// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "@forge-std/Test.sol";
import {TestERC20} from "./mocks/TestERC20.sol";
import {IERC20} from "@oz-v4.9.3/token/ERC20/IERC20.sol";
import {IWETH9} from "@uni-v3-periphery/interfaces/external/IWETH9.sol";
import {UniswapV3Factory} from "@uni-v3-core/UniswapV3Factory.sol";
import {ISwapRouter} from "@uni-v3-periphery/interfaces/ISwapRouter.sol";
import {NonfungiblePositionManager as NFTManager} from "@uni-v3-periphery/NonfungiblePositionManager.sol";
import {INonfungiblePositionManager} from "@uni-v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {SwapRouter} from "@uni-v3-periphery/SwapRouter.sol";
import {PoolAddress} from "@uni-v3-periphery/libraries/PoolAddress.sol";
import {console} from "forge-std/console.sol";
import {MockWeth} from "./mocks/MockWeth.sol";
import {UniswapV3Math} from "./libs/UniswapV3Lib.sol";

//uint160 sqrtPriceForCreatePool = UniswapV3Math.encodePriceSqrt(117_227_595_982_000, 137_200);

abstract contract UniswapV3Mocks is Test {
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
