# enigmaOS install media — build & flash the custom Arch ISO.
# The real logic lives in iso/build-iso.sh and iso/flash-usb.sh; this is just
# an ergonomic front-end. Run `make` (or `make help`) to list targets.

ISO_DIR := iso
ISO ?=
PORT ?= 8000
NETBOOT_HOST ?= 10.13.37.109
NETBOOT_PORT ?= 8480
NETBOOT_SSH ?= $(NETBOOT_HOST)

.PHONY: help iso netboot deploy flash serve clean clean-cache

help: ## Show this help
	@echo "enigmaOS install media — targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-7s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Examples:"
	@echo "  make iso                  build iso/out/enigmaos-*.iso"
	@echo "  make netboot deploy       build netboot artifacts and push them to the server"
	@echo "  make flash                write the newest ISO to a USB (prompts for the device)"
	@echo "  make flash ISO=path.iso   write a specific ISO"
	@echo "  make serve                host iso/out/ over HTTP on port 8000 (Ctrl-C to stop)"
	@echo "  make serve PORT=9000      same, on another port"
	@echo "  make clean                remove build artifacts"

iso: ## Build the install ISO (installs archiso if needed; needs sudo)
	$(ISO_DIR)/build-iso.sh

netboot: ## Build ISO + netboot artifacts (iso/out/arch) + embedded-script ipxe.efi
	NETBOOT=1 $(ISO_DIR)/build-iso.sh
	NETBOOT_HOST=$(NETBOOT_HOST) NETBOOT_PORT=$(NETBOOT_PORT) $(ISO_DIR)/build-ipxe.sh

deploy: ## Push netboot artifacts to the home server over SSH (resumable rsync)
	NETBOOT_HOST=$(NETBOOT_HOST) NETBOOT_PORT=$(NETBOOT_PORT) NETBOOT_SSH=$(NETBOOT_SSH) $(ISO_DIR)/deploy-netboot.sh

flash: ## Flash an ISO to USB — newest by default, or ISO=path (destructive; confirms)
	$(ISO_DIR)/flash-usb.sh $(ISO)

serve: ## Temporarily host iso/out/ over HTTP for LAN fetches (PORT=8000)
	$(ISO_DIR)/serve-iso.sh $(PORT)

clean: ## Remove build artifacts (iso/work, iso/out; keeps the package cache)
	sudo rm -rf $(ISO_DIR)/work $(ISO_DIR)/out

clean-cache: ## Remove the offline-repo cache (forces re-download + AUR rebuilds)
	sudo rm -rf $(ISO_DIR)/cache
