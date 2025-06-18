.PHONY: all install submodules update-submodules reset-submodules

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
	git submodule foreach --recursive 'git clean -dfx && git reset --hard'
	git submodule update --init --recursive
	@echo "Git submodules reset."
