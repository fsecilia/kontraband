# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

CC := /usr/bin/env cc
LD := /usr/bin/env ld
UTS_MACHINE ?= $(shell uname -m)

ifneq ($(KONTRA_VALIDATE_LINKER),)
src := $(M)
obj := $(M)
include $(M)/Kbuild
endif

.PHONY: modules clean
modules:
	@if [ -n "$(KONTRA_PROBE_CC_OUTPUT)" ]; then \
		printf '%s\n' '/usr/bin/env cc' > "$(KONTRA_PROBE_CC_OUTPUT)"; \
		printf '%s\n' '/usr/bin/env ld' > "$(KONTRA_PROBE_LD_OUTPUT)"; \
	elif [ -n "$(M)" ]; then \
		module="$$(sed -n 's/^obj-m += \(.*\)\.o$$/\1/p' "$(M)/Kbuild")"; \
		test -n "$$module"; \
		: > "$(M)/$$module.ko"; \
	fi
clean:
	@:
