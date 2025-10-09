.PHONY: all install submodules update-submodules reset-submodules verify-deployment build lint fmt test install-foundry

all: deps

# Install dependencies
deps: submodules

# Update git submodules
submodules:
	@echo "Updating git submodules..."
	git submodule update --init --recursive
	@echo "Git submodules updated." 

# Update git submodules to their latest remote versions
update-submodules:
	@echo "Updating git submodules to latest versions..."
	git submodule update --init --recursive --remote
	@echo "Git submodules updated." 

# Reset git submodules to their checked-in versions
reset-submodules:
	@echo "Resetting git submodules..."
	git submodule deinit --all -f
	git clean -dfx
	git submodule update --init --recursive
	@echo "Git submodules reset."

# Verify CREATE2 deployed contracts across chains with Etherscan verification
verify-deployment:
	@echo "Verifying CREATE2 contract deployments with Etherscan verification..."
	@if [ -z "$(ADDRESS)" ] || [ -z "$(SOURCE_CHAIN)" ] || [ -z "$(TARGET_CHAIN)" ]; then \
		echo "Usage: make verify-deployment ADDRESS=<contract_address> SOURCE_CHAIN=<chain_id> TARGET_CHAIN=<chain_id> [OPTIONS]"; \
		echo "Examples:"; \
		echo "  make verify-deployment ADDRESS=0x1234567890123456789012345678901234567890 SOURCE_CHAIN=42161 TARGET_CHAIN=1 SOURCE_ETHERSCAN_API_KEY=ABC123 TARGET_ETHERSCAN_API_KEY=DEF456"; \
		echo "  make verify-deployment ADDRESS=0x9876543210987654321098765432109876543210 SOURCE_CHAIN=137 TARGET_CHAIN=8453 CONSTRUCTOR_ARGS=0x000000000000000000000000..."; \
		echo "  make verify-deployment ADDRESS=0x1234... SOURCE_CHAIN=42161 TARGET_CHAIN=1 NO_ETHERSCAN=1"; \
		echo ""; \
		echo "Environment variables:"; \
		echo "  SOURCE_ETHERSCAN_API_KEY - API key for source chain Etherscan (required for verification)"; \
		echo "  TARGET_ETHERSCAN_API_KEY - API key for target chain Etherscan (required for verification)"; \
		echo "  CONSTRUCTOR_ARGS         - ABI-encoded constructor arguments (optional)"; \
		echo "  NO_ETHERSCAN             - Set to 1 to skip Etherscan verification"; \
		echo ""; \
		echo "Note: ADDRESS should be the same on both chains (CREATE2 deployment)"; \
		echo "      Contract must already be verified on SOURCE_CHAIN for Etherscan verification"; \
		exit 1; \
	fi
	@if [ "$(NO_ETHERSCAN)" = "1" ]; then \
		./scripts/verify-deployment.sh $(ADDRESS) $(SOURCE_CHAIN) $(TARGET_CHAIN) --no-verify-etherscan; \
	else \
		SOURCE_ETHERSCAN_API_KEY=$(SOURCE_ETHERSCAN_API_KEY) TARGET_ETHERSCAN_API_KEY=$(TARGET_ETHERSCAN_API_KEY) \
		CONSTRUCTOR_ARGS=$(CONSTRUCTOR_ARGS) \
		./scripts/verify-deployment.sh $(ADDRESS) $(SOURCE_CHAIN) $(TARGET_CHAIN); \
	fi

build:
	forge build

lint:
	forge fmt --check && forge lint

fmt:
	forge fmt

test:
	forge test -vvv

install-foundry:
	@command -v forge > /dev/null 2>&1 || (echo "forge not found; installing Foundry..." && curl -L https://foundry.paradigm.xyz | bash)
	@foundryup

storage-layout:
	@forge inspect src/TrailsRouter.sol storage-layout
	@forge inspect src/TrailsRouterShim.sol storage-layout
	@forge inspect src/TrailsIntentEntrypoint.sol storage-layout

coverage:
	@forge coverage --ir-minimum --no-match-coverage "test/|script/"
