# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

# Test-only addition to the generated workspace wrapper. This makes the focused object build use the same Kbuild and
# toolchain command as a normal module build instead of rebuilding that command in the test.
include Makefile

.PHONY: kontra-test-warning-object
kontra-test-warning-object:
	+$(MAKE) $(KBUILD_ARGS) \
	    $(KONTRA_DERIVED_KBUILD_ARGUMENTS) \
	    $(KONTRA_KBUILD_ARGUMENTS) \
	    $(KONTRA_REQUIRED_KBUILD_ARGUMENTS) \
	    W=123 projection/kernel/support.o
