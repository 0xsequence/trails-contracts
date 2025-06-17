.PHONY: all install submodules update-submodules

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
