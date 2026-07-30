# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

# x86-64 Kbuild disables x87. Kontraband allows x87 instructions for C++ so freestanding headers can use the ABI long
# double type. Follow the target kernel configuration here, not the architecture of the host running the test.
kontra_copy_fixture(project source build)
set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel")
kontra_configure("${source}" "${build}" "${kernel}" Ninja)
set(workspace "${build}/kontra/projects/kernel_project/modules/fixture_module/Release/workspace")

set(probe "${KONTRA_TEST_CASE_ROOT}/cxx-flags.mk")
file(WRITE "${probe}"
    "obj := .\n"
    "src := ${workspace}\n"
    "_c_flags := -mno-80387 -mno-sse\n"
    "modkern_cflags :=\n"
    "basename_flags :=\n"
    "modname_flags :=\n"
    "target-stem := target\n"
    "include ${workspace}/Kbuild\n"
    ".PHONY: probe\n"
    "probe:\n"
    "\t@printf '%s\\n' $(cxx_flags)\n"
)

kontra_run(make --no-print-directory -f "${probe}" CONFIG_X86_64=y probe)
if(NOT KONTRA_LAST_OUTPUT MATCHES "-mno-80387.*-m80387")
    message(FATAL_ERROR "x86-64 C++ flags did not restore x87 after Kbuild disabled it:\n${KONTRA_LAST_OUTPUT}")
endif()

kontra_run(make --no-print-directory -f "${probe}" CONFIG_X86_64= probe)
if(KONTRA_LAST_OUTPUT MATCHES "(^|[ \n])-m80387([ \n]|$)")
    message(FATAL_ERROR "non-x86-64 C++ flags unexpectedly enable x87:\n${KONTRA_LAST_OUTPUT}")
endif()
