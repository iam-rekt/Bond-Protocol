// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {BondFactory} from "../src/BondFactory.sol";
import {Bond} from "../src/Bond.sol";

import {BaseTest} from "./BaseTest.t.sol";

import {IUniswapSwapRouter} from "../src/interfaces/IUniswap.sol";

contract BondTest is BaseTest {
    event MintBonds(address indexed user, uint256 amountUsdc, uint256 bondsMinted, uint256 strikePrice);
    event RedeemBonds(address indexed user, uint256 amountBonds, uint256 amountInAsset);
    event FinalizeBondPrice(uint256 sqrtExpiryPriceX96);

    function setUp() public override {
        super.setUp();
    }

    function test_BondInitialization() public {
        assertEq(bond.name(), BOND_NAME);
        assertEq(bond.symbol(), BOND_SYMBOL);
        assertEq(bond.decimals(), BOND_DECIMALS);
        assertEq(bond.maxUsdc(), MAX_USDC);
        assertEq(bond.sqrtStrikePriceX96(), SQRT_STRIKE_PRICE_X96);
        assertEq(bond.bondFactory(), address(factory));
        assertEq(bond.issuanceEnd(), block.timestamp + 7 days);
        assertEq(bond.bondExpiry(), block.timestamp + 14 days);

        assertTrue(factory.isBond(address(bond)));
    }

    function test_MintBond() public {
        uint256 usdcAmount = 1000e6;

        // Approve USDC spending
        vm.startPrank(user);
        IERC20(USDC).approve(address(bond), usdcAmount);

        // Record balances before mint
        uint256 userUsdcBefore = IERC20(USDC).balanceOf(user);
        uint256 bondUsdcBefore = IERC20(USDC).balanceOf(address(bond));
        uint256 userBondsBefore = bond.balanceOf(user);

        // Mint bonds
        bond.mintBonds(usdcAmount);
        vm.stopPrank();

        // Verify balances after mint
        assertEq(IERC20(USDC).balanceOf(user), userUsdcBefore - usdcAmount);
        assertEq(IERC20(USDC).balanceOf(address(bond)), bondUsdcBefore + usdcAmount);
        assertEq(bond.balanceOf(user), userBondsBefore + usdcAmount);
        assertEq(bond.usdcDeposited(), usdcAmount);
    }

    function test_RevertIf_MintAfterIssuanceEnd() public {
        timeTravel(7 days + 1);

        vm.startPrank(user);
        IERC20(USDC).approve(address(bond), 1000e6);

        vm.expectRevert("Bond: cannot mint after bond issuanceEnd");
        bond.mintBonds(1000e6);
        vm.stopPrank();
    }

    function test_RevertIf_MintExceedsMaxUsdc() public {
        uint256 exceedAmount = MAX_USDC + 1;

        vm.startPrank(user);
        IERC20(USDC).approve(address(bond), exceedAmount);

        vm.expectRevert("Bond: exceeds max USDC deposit");
        bond.mintBonds(exceedAmount);
        vm.stopPrank();
    }

    function test_RevertIf_MintZeroAmount() public {
        vm.startPrank(user);
        IERC20(USDC).approve(address(bond), 1);

        vm.expectRevert("Bond: amount must be > 0");
        bond.mintBonds(0);
        vm.stopPrank();
    }

    function test_MintBondEvent() public {
        uint256 usdcAmount = 1000e6;

        vm.startPrank(user);
        IERC20(USDC).approve(address(bond), usdcAmount);

        vm.expectEmit(true, false, false, true);
        emit MintBonds(user, usdcAmount, usdcAmount, SQRT_STRIKE_PRICE_X96);

        bond.mintBonds(usdcAmount);
        vm.stopPrank();
    }

    function test_SetPool() public {
        address pool = makeAddr("pool");

        vm.prank(owner);
        bond.setPool(pool);

        assertEq(bond.assetUSDCPool(), pool);
    }

    function test_RevertIf_NonOwnerSetsPool() public {
        vm.prank(user);
        vm.expectRevert("UNAUTHORIZED");
        bond.setPool(makeAddr("pool"));
    }

    function test_RedeemBondsForUsdc() public {
        uint256 usdcAmount = 1000e6;
        vm.startPrank(user);
        IERC20(USDC).approve(address(bond), usdcAmount);
        bond.mintBonds(usdcAmount);
        vm.stopPrank();

        // set pool
        vm.prank(owner);
        bond.setPool(address(assetUsdcPool));

        uint256 userBonds = bond.balanceOf(user);
        uint256 userUsdc = IERC20(USDC).balanceOf(user);
        timeTravel(20 days);
        vm.prank(user);
        bond.redeemBonds(userBonds);
        vm.stopPrank();

        assertEq(bond.balanceOf(user), 0);
        assertEq(IERC20(USDC).balanceOf(user), userUsdc + usdcAmount);
    }

    function test_RedeemBondsForAsset() public {
        // buy asset to increase Asset price to be above strike price
        vm.startPrank(swapper);
        IERC20(USDC).approve(address(uniswapRouter), 1e6);
        IUniswapSwapRouter.ExactInputSingleParams memory params = IUniswapSwapRouter.ExactInputSingleParams({
            tokenIn: USDC,
            tokenOut: address(assetToken),
            tickSpacing: TICK_SPACING,
            recipient: address(swapper),
            deadline: 999999999999999999999999999999,
            amountIn: 1e6,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        uniswapRouter.exactInputSingle(params);
        vm.stopPrank();

        uint256 usdcAmount = 1000e6;
        vm.startPrank(user);
        IERC20(USDC).approve(address(bond), usdcAmount);
        bond.mintBonds(usdcAmount);
        vm.stopPrank();

        assertEq(bond.balanceOf(user), usdcAmount);

        vm.prank(owner);
        bond.setPool(address(assetUsdcPool));

        uint256 userBonds = bond.balanceOf(user);
        uint256 userAsset = assetToken.balanceOf(user);
        assertEq(userAsset, 0);
        timeTravel(14 days);
        vm.prank(user);
        bond.redeemBonds(userBonds);
        vm.stopPrank();

        // as pool is almost 1 Asset ~= 1 USDC expected asset from bond should be
        // equal to userBonds by some delta
        uint256 expectedAssetFromBond = userBonds * 1e12;
        assertEq(bond.balanceOf(user), 0);
        // don't want to do fine calculations so delta is 2 asset for 1000e6 USDC
        assertApproxEqAbs(assetToken.balanceOf(user), expectedAssetFromBond, 2e18);
    }

    function test_SwapUsdcForAsset() public {
        // just making sure that tick price is set correctly
        uint256 usdcAmount = 1e6;
        uint256 userAssetBalBefore = assetToken.balanceOf(user);

        assertEq(userAssetBalBefore, 0);

        vm.startPrank(user);
        IERC20(USDC).approve(address(uniswapRouter), usdcAmount);
        IUniswapSwapRouter.ExactInputSingleParams memory params = IUniswapSwapRouter.ExactInputSingleParams({
            tokenIn: USDC,
            tokenOut: address(assetToken),
            tickSpacing: TICK_SPACING,
            recipient: address(user),
            deadline: 999999999999999999999999999999,
            amountIn: usdcAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        uniswapRouter.exactInputSingle(params);
        vm.stopPrank();
        uint256 userAssetBalAfter = assetToken.balanceOf(user);
        // 1e6 USDC ~= 1e18Asset
        assertApproxEqAbs(userAssetBalAfter, 996e15, 1e15);
    }

    function test_RevertIf_RedeemBeforeIssuanceEnd() public {
        uint256 usdcAmount = 1000e6;
        vm.startPrank(user);
        IERC20(USDC).approve(address(bond), usdcAmount);
        bond.mintBonds(usdcAmount);

        vm.expectRevert("Bond: not yet matured");
        bond.redeemBonds(usdcAmount);
        vm.stopPrank();
    }

    function test_RevertIf_RedeemZeroAmount() public {
        timeTravel(14 days);

        vm.prank(user);
        vm.expectRevert("Bond: amount must be > 0");
        bond.redeemBonds(0);
    }

    function test_RevertIfBondExpiryNotReached() public {
        timeTravel(13 days);

        vm.prank(user);
        vm.expectRevert("Bond: not yet matured");
        bond.redeemBonds(1);
    }

    function test_RevertIf_RedeemExceedsBalance() public {
        uint256 usdcAmount = 1000e6;

        // Mint bonds
        vm.startPrank(user);
        IERC20(USDC).approve(address(bond), usdcAmount);
        bond.mintBonds(usdcAmount);
        vm.stopPrank();

        vm.startPrank(owner);
        bond.setPool(address(assetUsdcPool));
        vm.stopPrank();

        uint256 amount = bond.balanceOf(user);
        timeTravel(14 days);
        vm.prank(user);
        // panic: arithmetic underflow or overflow (0x11)
        vm.expectRevert(hex"4e487b710000000000000000000000000000000000000000000000000000000000000011");
        bond.redeemBonds(amount + 1);
    }

    function test_RescueUSDC() public {
        // First mint some bonds to get USDC in the contract
        uint256 usdcAmount = 1000e6;
        vm.startPrank(user);
        IERC20(USDC).approve(address(bond), usdcAmount);
        bond.mintBonds(usdcAmount);
        vm.stopPrank();

        // Record balances before rescue
        uint256 ownerBalanceBefore = IERC20(USDC).balanceOf(owner);
        uint256 bondBalanceBefore = IERC20(USDC).balanceOf(address(bond));

        // Rescue USDC
        vm.prank(owner);
        bond.rescueAsset(USDC, usdcAmount);

        // Verify balances
        assertEq(IERC20(USDC).balanceOf(owner), ownerBalanceBefore + usdcAmount);
        assertEq(IERC20(USDC).balanceOf(address(bond)), bondBalanceBefore - usdcAmount);
    }

    function test_RescueAsset() public {
        // Send some tokens to bond contract
        address tokenToRescue = address(assetToken);
        uint256 amount = 1000e18;
        vm.prank(owner);
        assetToken.transfer(address(bond), amount);

        // Record balances before rescue
        uint256 ownerBalanceBefore = IERC20(tokenToRescue).balanceOf(owner);
        uint256 bondBalanceBefore = IERC20(tokenToRescue).balanceOf(address(bond));

        // Rescue tokens
        vm.prank(owner);
        bond.rescueAsset(tokenToRescue, amount);

        // Verify balances
        assertEq(IERC20(tokenToRescue).balanceOf(owner), ownerBalanceBefore + amount);
        assertEq(IERC20(tokenToRescue).balanceOf(address(bond)), bondBalanceBefore - amount);
    }

    function test_RevertIf_NonOwnerRescuesAsset() public {
        vm.prank(user);
        vm.expectRevert("UNAUTHORIZED");
        bond.rescueAsset(address(assetToken), 1000e18);
    }
}
