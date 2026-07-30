# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

CC := $(CURDIR)/compiler-wrapper
LD := /usr/bin/true
UTS_MACHINE := $(KONTRA_TEST_PROCESSOR)
KBUILD_CPPFLAGS += --target=$(KONTRA_TEST_TRIPLE) -DKONTRA_FAKE_CPPFLAG=1
KBUILD_CFLAGS += -Werror -DKONTRA_FAKE_CFLAG=1

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
