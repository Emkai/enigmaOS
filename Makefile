# enigmaOS install media — build & flash the custom Arch ISO.
# The real logic lives in iso/build-iso.sh and iso/flash-usb.sh; this is just
# an ergonomic front-end. Run `make` (or `make help`) to list targets.

ISO_DIR := iso
ISO ?=

.PHONY: help iso flash clean

help: ## Show this help
	@echo "enigmaOS install media — targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-7s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Examples:"
	@echo "  make iso                  build iso/out/enigmaos-*.iso"
	@echo "  make flash                write the newest ISO to a USB (prompts for the device)"
	@echo "  make flash ISO=path.iso   write a specific ISO"
	@echo "  make clean                remove build artifacts"

iso: ## Build the install ISO (installs archiso if needed; needs sudo)
	$(ISO_DIR)/build-iso.sh

flash: ## Flash an ISO to USB — newest by default, or ISO=path (destructive; confirms)
	$(ISO_DIR)/flash-usb.sh $(ISO)

clean: ## Remove build artifacts (iso/work, iso/out)
	sudo rm -rf $(ISO_DIR)/work $(ISO_DIR)/out
