// script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {MintableERC20} from "../src/MintableERC20.sol";
import {BondFactory} from "../src/BondFactory.sol";
import {CREATE2Helper} from "../src/lib/CREATE2Helper.sol";

contract DeployFactoryAndMintableERC20 is Script {
    // This is the address we need our token to be "less than"
    // to ensure it becomes token0 in a liquidity pool pair.
    address public constant USDC = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;

    // Foundry's deterministic CREATE2 deployer address.
    // Using this ensures our predicted address matches the actual deployment address.
    address private constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Define a struct to hold deployment parameters, reducing stack depth.
    struct TokenConfig {
        string name;
        string symbol;
        uint8 decimals;
        uint256 initialSupply;
        address factory;
        address owner;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the BondFactory
        BondFactory factory = new BondFactory(deployer);
        console2.log("BondFactory deployed at:", address(factory));

        // 2. Populate the configuration struct in memory
        TokenConfig memory config = TokenConfig({
            name: "HyperStrategy",
            symbol: "HSTR",
            decimals: 18,
            initialSupply: 1000000000000000000000000,
            factory: address(factory),
            owner: deployer
        });

        // 3. Prepare for MintableERC20 Deployment
        bytes memory constructorArgs =
            abi.encode(config.name, config.symbol, config.decimals, config.initialSupply, config.factory, config.owner);
        bytes memory creationCode = type(MintableERC20).creationCode;

        // 4. Find a suitable salt and deploy the MintableERC20
        console2.log("Searching for a deployment address that is less than USDC:", USDC);

        MintableERC20 token;
        bytes32 salt;
        address predictedAddress;
        uint256 maxIterations = 1_000_000; // Safety break to prevent infinite loops

        for (uint256 i = 0; i < maxIterations; i++) {
            salt = keccak256(abi.encodePacked("hyperstrategy.token.v1", i));

            // *** THE FIX IS HERE ***
            // Predict the address using the correct CREATE2_DEPLOYER, not address(this).
            predictedAddress = CREATE2Helper.predictAddress(CREATE2_DEPLOYER, salt, constructorArgs, creationCode);

            // Condition: The predicted address must be available AND less than the USDC address.
            if (predictedAddress < USDC && predictedAddress.code.length == 0) {
                console2.log("Found suitable address at iteration %s:", i, predictedAddress);

                // Deploy the contract using the successful salt
                token = new MintableERC20{salt: salt}(
                    config.name, config.symbol, config.decimals, config.initialSupply, config.factory, config.owner
                );

                // Sanity check to ensure deployment happened at the predicted address
                require(address(token) == predictedAddress, "Deployment address mismatch");
                break; // Exit the loop once successfully deployed
            }
        }

        // Final check to ensure the token was deployed. If not, the script will fail.
        require(address(token) != address(0), "Failed to find a suitable deployment address within max iterations.");

        console2.log("Success! MintableERC20 deployed at:", address(token));

        vm.stopBroadcast();
    }
}
