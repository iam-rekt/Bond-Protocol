// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {BondFactory} from "../src/BondFactory.sol";
import {Bond} from "../src/Bond.sol";
import {MintableERC20} from "../src/MintableERC20.sol";
import {TickMath} from "../src/lib/external/TickMath.sol";
import {CREATE2Helper} from "../src/lib/CREATE2Helper.sol";
import {
    IUniswapSwapRouter,
    IUniswapV3Factory,
    INonfungiblePositionManager,
    IUniswapV3Pool
} from "../src/interfaces/IUniswap.sol";

contract BaseTest is Test {
    // Contracts
    BondFactory public factory;
    MintableERC20 public assetToken;
    Bond public bond;

    // Actors
    address public owner;
    address public user;
    address public liquidityProvider;
    address public swapper;

    // Constants - Base Mainnet Addresses
    address public constant USDC = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
    address public constant USDC_WHALE = 0x8cC81c5C09394CEaCa7a53be5f547AE719D75dFC;
    // NOTE: These addresses have been updated to Kittenswap's addresses
    address public constant NONFUNGIBLE_POSITION_MANAGER = 0xB9201e89f94a01FF13AD4CAeCF43a2e232513754;
    address public constant SWAP_ROUTER = 0x8fFDB06039B1b8188c2C721Dc3C435B5773D7346;
    address public constant FACTORY = 0x2E08F5Ff603E4343864B14599CAeDb19918BDCaF;

    // Uniswap Interfaces
    IUniswapV3Factory public uniswapFactory;
    IUniswapSwapRouter public uniswapRouter;
    INonfungiblePositionManager public nonfungiblePositionManager;
    IUniswapV3Pool public assetUsdcPool;

    // Bond Default Parameters
    string public BOND_NAME = "Test Bond";
    string public BOND_SYMBOL = "TBOND";
    uint8 public BOND_DECIMALS = 18;
    int24 public STARTING_TICK = -276200;
    int24 public ACTUAL_TICK = -276310;
    // ADDED: Tick spacing constant. Assumes 200 for 1% fee pools. Please verify this value.
    int24 public constant TICK_SPACING = 200;
    uint160 public SQRT_STRIKE_PRICE_X96;
    uint256 public MAX_USDC = 1000000e6;

    // Asset Token Default Parameters
    string public ASSET_NAME = "Asset Token";
    string public ASSET_SYMBOL = "AT";
    uint8 public ASSET_DECIMALS = 18;
    uint256 public ASSET_SUPPLY = 10000000e18;

    function setUp() public virtual {
        // Fork Base mainnet
        vm.createSelectFork(vm.envString("RPC_URL"));

        owner = makeAddr("owner");
        user = makeAddr("user");
        liquidityProvider = makeAddr("liquidityProvider");
        swapper = makeAddr("swapper");
        // Setup Uniswap interfaces
        uniswapFactory = IUniswapV3Factory(FACTORY);
        uniswapRouter = IUniswapSwapRouter(SWAP_ROUTER);
        nonfungiblePositionManager = INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER);

        SQRT_STRIKE_PRICE_X96 = TickMath.getSqrtRatioAtTick(ACTUAL_TICK);

        // Deploy contracts
        vm.startPrank(owner);

        // Deploy bond factory
        factory = new BondFactory(owner);

        // Deploy asset token
        bytes memory constructorArgs =
            abi.encode(ASSET_NAME, ASSET_SYMBOL, ASSET_DECIMALS, ASSET_SUPPLY, address(factory), owner);
        bytes memory creationCode = type(MintableERC20).creationCode;
        (bytes32 salt,) = CREATE2Helper.generateSalt(owner, constructorArgs, creationCode, USDC, false);
        assetToken = new MintableERC20{salt: salt}(
            ASSET_NAME, ASSET_SYMBOL, ASSET_DECIMALS, ASSET_SUPPLY, address(factory), owner
        );

        // UPDATED: Pool creation is now handled by the NonfungiblePositionManager's mint function.
        // We will define the pool address after minting liquidity.
        factory.setAssetToken(address(assetToken));

        // Deploy bond
        bond = Bond(
            factory.createBondProgram(
                BOND_NAME,
                BOND_SYMBOL,
                BOND_DECIMALS,
                SQRT_STRIKE_PRICE_X96,
                MAX_USDC,
                block.timestamp + 7 days, // issuanceEnd
                block.timestamp + 14 days // bondExpiry
            )
        );
        vm.stopPrank();

        // Fund test accounts with USDC
        vm.startPrank(USDC_WHALE);
        IERC20(USDC).transfer(user, 10000e6);
        IERC20(USDC).transfer(liquidityProvider, 10000e6);
        IERC20(USDC).transfer(swapper, 10000e6);
        vm.stopPrank();

        vm.startPrank(owner);
        assetToken.transfer(liquidityProvider, 1000000e18);
        vm.stopPrank();

        // UPDATED: Add liquidity to the pool.
        // This will also create the pool since we provide a non-zero sqrtPriceX96.
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(assetToken),
            token1: USDC,
            tickSpacing: TICK_SPACING, // UPDATED: from fee
            sqrtPriceX96: SQRT_STRIKE_PRICE_X96, // ADDED: to initialize pool
            tickLower: -276200 - 2000,
            tickUpper: -276200 + 2000,
            amount0Desired: 100000e18,
            amount1Desired: 1000e6,
            amount0Min: 0,
            amount1Min: 0,
            recipient: liquidityProvider,
            deadline: block.timestamp + 1000000
        });

        vm.startPrank(liquidityProvider);
        // approve asset and usdc to nonfungiblePositionManager
        assetToken.approve(address(nonfungiblePositionManager), 100000e18);
        IERC20(USDC).approve(address(nonfungiblePositionManager), 1000e6);
        nonfungiblePositionManager.mint(params);
        vm.stopPrank();

        // UPDATED: Get the pool address from the factory after it has been created.
        assetUsdcPool = IUniswapV3Pool(uniswapFactory.getPool(address(assetToken), USDC, TICK_SPACING));
    }

    // Helper function to create a new bond with custom parameters
    function createBond(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint160 sqrtStrikePriceX96,
        uint256 maxUsdc,
        uint256 issuanceEnd,
        uint256 bondExpiry
    ) internal returns (Bond) {
        vm.prank(owner);
        return Bond(
            factory.createBondProgram(name, symbol, decimals, sqrtStrikePriceX96, maxUsdc, issuanceEnd, bondExpiry)
        );
    }

    // Helper to move time forward
    function timeTravel(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }
}
