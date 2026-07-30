# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

UTS_MACHINE ?= $(shell uname -m)

ifneq ($(KONTRA_VALIDATE_LINKER),)
src := $(M)
obj := $(M)
include $(M)/Kbuild
endif

.PHONY: modules modules_install clean
modules:
	@if [ -n "$(KONTRA_PROBE_CC_OUTPUT)" ]; then \
		printf '%s\n' '$(CC)' > "$(KONTRA_PROBE_CC_OUTPUT)"; \
		printf '%s\n' '$(LD)' > "$(KONTRA_PROBE_LD_OUTPUT)"; \
	elif [ -n "$(M)" ]; then \
		if [ -n "$(KONTRA_TEST_SERIALIZE)" ]; then \
			lock="$(M)/.kontra-kbuild-lock"; \
			if ! mkdir "$$lock" 2>/dev/null; then \
				echo "concurrent Kbuild invocation in $(M)" >&2; \
				exit 1; \
			fi; \
			trap 'rmdir "$$lock"' EXIT INT TERM; \
			sleep 0.25; \
		fi; \
		printf '%s\n' \
			'ARCH=$(ARCH)' \
			'V=$(V)' \
			'LLVM=$(LLVM)' \
			'CROSS_COMPILE=$(CROSS_COMPILE)' \
			'KONTRA_TEST_ARGUMENT=$(KONTRA_TEST_ARGUMENT)' \
			'KONTRA_TEST_SECOND=$(KONTRA_TEST_SECOND)' \
			'KONTRA_HASH_0=$(KONTRA_HASH_0)' \
			'KONTRA_HASH_1=$(KONTRA_HASH_1)' \
			'KONTRA_HASH_2=$(KONTRA_HASH_2)' \
			'KONTRA_HASH_3=$(KONTRA_HASH_3)' \
			'LDFLAGS_MODULE=$(LDFLAGS_MODULE)' \
			'LDFLAGS_MODULE_ORIGIN=$(origin LDFLAGS_MODULE)' \
			'CONFIG_DEBUG_INFO_BTF_MODULES=$(CONFIG_DEBUG_INFO_BTF_MODULES)' \
			'CONFIG_DEBUG_INFO_BTF_MODULES_ORIGIN=$(origin CONFIG_DEBUG_INFO_BTF_MODULES)' \
			>> "$(M)/kbuild-arguments.txt"; \
		module="$$(sed -n 's/^obj-m += \(.*\)\.o$$/\1/p' "$(M)/Kbuild")"; \
		test -n "$$module"; \
		printf '%s\n' modules >> "$(M)/kbuild-invocations.txt"; \
		: > "$(M)/$$module.ko"; \
	fi
modules_install:
	@if [ -n "$(M)" ]; then \
		printf '%s\n' \
			'INSTALL_MOD_PATH=$(INSTALL_MOD_PATH)' \
			'INSTALL_MOD_STRIP=$(INSTALL_MOD_STRIP)' \
			>> "$(M)/kbuild-install-arguments.txt"; \
		printf '%s\n' modules_install >> "$(M)/kbuild-invocations.txt"; \
	fi

clean:
	@if [ -n "$(M)" ]; then rm -f "$(M)"/*.ko; fi
