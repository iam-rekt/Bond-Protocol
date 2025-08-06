// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {BondFactory} from "../src/BondFactory.sol";
import {MintableERC20} from "../src/MintableERC20.sol";

contract BondFactoryTest is Test {
    BondFactory public factory;
    MintableERC20 public assetToken;
    address public owner;

    event BondCreated(address indexed bondAddress, string name, string symbol);

    function setUp() public {
        owner = makeAddr("owner");

        // Deploy factory
        vm.prank(owner);
        factory = new BondFactory(owner);

        // Deploy and set asset token
        assetToken = new MintableERC20("Asset Token", "AT", 18, 1000000e18, address(factory), owner);
        vm.prank(owner);
        factory.setAssetToken(address(assetToken));
    }

    function test_Constructor() public {
        assertEq(factory.owner(), owner);
    }

    function predictBondAddress(address deployer) public view returns (address) {
        uint256 nonce = vm.getNonce(deployer);

        bytes memory data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, uint8(nonce));

        bytes32 hash = keccak256(data);
        return address(uint160(uint256(hash)));
    }

    function test_CreateBondProgram() public {
        string memory name = "Test Bond";
        string memory symbol = "TBOND";
        uint8 decimals = 18;
        uint160 sqrtStrikePriceX96 = 1e18;
        uint256 maxUsdc = 1000000e6;
        uint256 issuanceEnd = block.timestamp + 7 days;
        uint256 bondExpiry = block.timestamp + 14 days;

        // Predict the address before deployment
        address predictedAddress = predictBondAddress(address(factory));

        vm.prank(owner);

        // Update event expectation with predicted address
        vm.expectEmit(true, false, false, true);
        emit BondCreated(predictedAddress, name, symbol);

        address bondAddress =
            factory.createBondProgram(name, symbol, decimals, sqrtStrikePriceX96, maxUsdc, issuanceEnd, bondExpiry);

        assertEq(bondAddress, predictedAddress, "Predicted address should match actual address");
        assertTrue(factory.isBond(bondAddress));
    }

    function test_RevertIf_NonOwnerCreatesBond() public {
        vm.prank(makeAddr("nonOwner"));
        vm.expectRevert("UNAUTHORIZED");

        factory.createBondProgram(
            "Test Bond", "TBOND", 18, 1e18, 1000000e6, block.timestamp + 7 days, block.timestamp + 14 days
        );
    }

    function test_SetAssetToken() public {
        // Deploy new factory to test setting asset token
        vm.prank(owner);
        BondFactory newFactory = new BondFactory(owner);

        address newAssetToken = makeAddr("newAssetToken");
        vm.prank(owner);
        newFactory.setAssetToken(newAssetToken);

        assertEq(newFactory.assetToken(), newAssetToken);
    }

    function test_RevertIf_NonOwnerSetsAssetToken() public {
        vm.prank(makeAddr("nonOwner"));
        vm.expectRevert("UNAUTHORIZED");
        factory.setAssetToken(makeAddr("newAssetToken"));
    }

    function test_RevertIf_SetAssetTokenToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("BondFactory: invalid token address");
        factory.setAssetToken(address(0));
    }

    function test_RevertIf_AssetTokenAlreadySet() public {
        vm.prank(owner);
        vm.expectRevert("BondFactory: asset token already set");
        factory.setAssetToken(makeAddr("newAssetToken"));
    }

    function test_MintOnRedemption() public {
        // Create a bond first
        vm.prank(owner);
        address bondAddress = factory.createBondProgram(
            "Test Bond", "TBOND", 18, 1e18, 1000000e6, block.timestamp + 7 days, block.timestamp + 14 days
        );

        // Test minting through bond
        address recipient = makeAddr("recipient");
        uint256 amount = 1000e18;

        assertEq(assetToken.balanceOf(recipient), 0);

        vm.prank(bondAddress);
        factory.mintOnRedemption(amount, recipient);

        assertEq(assetToken.balanceOf(recipient), amount);
    }

    function test_RevertIf_NonBondCallsMintOnRedemption() public {
        vm.prank(makeAddr("nonBond"));
        vm.expectRevert("BondFactory: not a valid bond");
        factory.mintOnRedemption(1000e18, makeAddr("recipient"));
    }
}
