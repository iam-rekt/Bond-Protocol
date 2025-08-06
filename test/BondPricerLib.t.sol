// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {BondPricerLib} from "../src/lib/BondPricerLib.sol";
import {TickMath} from "../src/lib/external/TickMath.sol";

contract BondPricerLibTest is Test {
    function test_convertBondToMintAmountWith1To1StrikePrice() public {
        uint256 amountBonds = 3310e6;
        // 1:1 strike price
        uint160 strikePrice = TickMath.getSqrtRatioAtTick(0);

        uint256 amountInAsset = BondPricerLib.getAssetAmountFromBond(amountBonds, strikePrice);

        assertEq(amountInAsset, 3310e6);
    }

    function test_convertBondToMintAmountWithStrikePrice() public {
        uint256 amountBonds = 1e6;
        // 1: 10.67 usdc per asset
        int24 tick = -300000;
        uint160 strikePrice = TickMath.getSqrtRatioAtTick(tick);
        uint256 amountInAsset = BondPricerLib.getAssetAmountFromBond(amountBonds, strikePrice);
        assertEq(amountInAsset / 1e16, 1067);
    }

    function test_zeroBondAmount() public {
        uint256 bondAmount = 0;
        uint160 strikePrice = TickMath.getSqrtRatioAtTick(0);

        uint256 amountInAsset = BondPricerLib.getAssetAmountFromBond(bondAmount, strikePrice);
        assertEq(amountInAsset, 0);
    }

    function test_veryHighStrikePrice() public {
        uint256 amountBonds = 2e6; // 2 USDC
        int24 tick = 10000;
        uint160 strikePrice = TickMath.getSqrtRatioAtTick(tick);

        uint256 amountInAsset = BondPricerLib.getAssetAmountFromBond(amountBonds, strikePrice);
        assertTrue(amountInAsset > 0, "Should not be zero");
        assertTrue(amountInAsset < 1e16, "Asset amount should be very small");
    }

    function test_veryLowStrikePrice() public {
        uint256 amountBonds = 1e6; // 1 USDC
        int24 tick = -10000;
        uint160 strikePrice = TickMath.getSqrtRatioAtTick(tick);

        uint256 amountInAsset = BondPricerLib.getAssetAmountFromBond(amountBonds, strikePrice);

        assertTrue(amountInAsset > 1e6, "Should get more than 1 token if it's cheaper");
    }
}
