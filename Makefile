include .env
export $(shell sed 's/=.*//' .env)

.PHONY: deploy_factory_and_mintableERC20 check_mintableERC20

deploy_factory_and_mintableERC20:
	@echo "Deploying Factory and MintableERC20 to Base Mainnet"
	@forge script script/Deploy.s.sol:DeployFactoryAndMintableERC20 --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) --verify --broadcast -vv
	@echo "Deployment completed!"

check_factory_and_mintableERC20:
	@echo "Checking Factory and MintableERC20 deployment"
	@forge script script/Deploy.s.sol:DeployFactoryAndMintableERC20 --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY)  -vv
	@echo "Check completed!" 