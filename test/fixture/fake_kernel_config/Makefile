# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

UTS_MACHINE ?= $(shell uname -m)

kontra_input_cc := $(CC)
kontra_input_ld := $(LD)
ifneq ($(LLVM),)
CC := clang
LD := ld.lld
endif
ifneq ($(KONTRA_VALIDATE_LINKER),)
src := $(M)
obj := $(M)
include $(M)/Kbuild
endif

.PHONY: modules clean
modules:
	@if [ -n "$(KONTRA_PROBE_CC_OUTPUT)" ]; then \
		effective_cc="$(CC)"; effective_ld="$(LD)"; \
		printf '%s\n' "/usr/bin/env cc -DFAKE_CC=$$effective_cc" > "$(KONTRA_PROBE_CC_OUTPUT)"; \
		printf '%s\n' '/usr/bin/true' > "$(KONTRA_PROBE_LD_OUTPUT)"; \
		printf '%s\n' \
			"CC=$(kontra_input_cc)" \
			"LD=$(kontra_input_ld)" \
			"LLVM=$(LLVM)" \
			"EFFECTIVE_CC=$$effective_cc" \
			"EFFECTIVE_LD=$$effective_ld" \
			> "$(M)/toolchain-arguments.txt"; \
	elif [ -n "$(M)" ]; then \
		effective_cc="$(CC)"; effective_ld="$(LD)"; \
		printf '%s\n' \
			"CC=$(kontra_input_cc)" \
			"LD=$(kontra_input_ld)" \
			"LLVM=$(LLVM)" \
			"EFFECTIVE_CC=$$effective_cc" \
			"EFFECTIVE_LD=$$effective_ld" \
			> "$(M)/toolchain-arguments.txt"; \
		module="$$(sed -n 's/^obj-m += \(.*\)\.o$$/\1/p' "$(M)/Kbuild")"; \
		test -n "$$module"; \
		: > "$(M)/$$module.ko"; \
	fi
clean:
	@:
