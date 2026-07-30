# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

CC := /usr/bin/env cc
LD := /usr/bin/true
UTS_MACHINE := x86_64
KBUILD_CPPFLAGS += --target=x86_64-linux-gnu -DKONTRA_FAKE_CPPFLAG=1
KBUILD_CFLAGS += -m64 -Werror -DKONTRA_FAKE_CFLAG=1

ifneq ($(KONTRA_VALIDATE_LINKER),)
src := $(M)
obj := $(M)
include $(M)/Kbuild
endif

.PHONY: modules clean
modules:
	@:
clean:
	@:
