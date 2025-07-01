.PHONY: all install submodules update-submodules reset-submodules verify-deployment

all: install

# Install dependencies
install: submodules

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

# Verify deployed contracts across chains
verify-deployment:
	@echo "Verifying contract deployments..."
	@if [ -z "$(CONTRACT)" ]; then \
		echo "Usage: make verify-deployment CONTRACT=<contract_name> [SOURCE_CHAIN=<chain_id>] [TARGET_CHAIN=<chain_id>]"; \
		echo "Examples:"; \
		echo "  make verify-deployment CONTRACT=AnypayRelaySapientSigner SOURCE_CHAIN=42161 TARGET_CHAIN=1"; \
		echo "  make verify-deployment CONTRACT=AnypayRelaySapientSigner SOURCE_CHAIN=42161"; \
		exit 1; \
	fi
	@if [ -n "$(TARGET_CHAIN)" ]; then \
		./scripts/verify-deployment.sh $(CONTRACT) $(SOURCE_CHAIN) $(TARGET_CHAIN); \
	elif [ -n "$(SOURCE_CHAIN)" ]; then \
		./scripts/verify-deployment.sh $(CONTRACT) $(SOURCE_CHAIN); \
	else \
		echo "SOURCE_CHAIN parameter is required"; \
		exit 1; \
	fi
