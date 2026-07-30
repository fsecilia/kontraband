# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

find_program(KONTRA_TEST_MAKE_EXECUTABLE NAMES make gmake REQUIRED NO_CACHE)
set(root "${KONTRA_TEST_CASE_ROOT}/kbuild-compatibility")
file(REMOVE_RECURSE "${root}")
file(MAKE_DIRECTORY "${root}")
file(READ "${KONTRA_TEST_SOURCE_ROOT}/cmake/package/templates/kbuild_compatibility.in" compatibility)

set(required [=[
obj := @ROOT@
CC := cc
depfile := depfile
_c_flags := flags
modkern_cflags := flags
basename_flags := flags
modname_flags := flags
target-stem := target
cmd = true
if_changed_rule = true
FORCE:
.PHONY: all
all: $(obj)/kontra-kbuild-compatibility
]=])
string(REPLACE "@ROOT@" "${root}" required "${required}")

# Evaluate the generated Kbuild compatibility probe against one synthetic symbol set.
function(kontra_check_compatibility name definitions expected_result expected_text)
    file(WRITE "${root}/Makefile" "${definitions}\n${compatibility}\n")
    execute_process(
        COMMAND "${KONTRA_TEST_MAKE_EXECUTABLE}" --no-print-directory -f "${root}/Makefile" all
        RESULT_VARIABLE result
        OUTPUT_VARIABLE output
        ERROR_VARIABLE error
    )
    if(expected_result STREQUAL "PASS")
        if(NOT result EQUAL 0)
            message(FATAL_ERROR "${name} unexpectedly failed:\n${output}${error}")
        endif()
    elseif(result EQUAL 0 OR NOT "${output}${error}" MATCHES "${expected_text}")
        message(FATAL_ERROR "${name} did not fail with /${expected_text}/:\n${output}${error}")
    endif()
endfunction()

kontra_check_compatibility(
    missing-required
    "${required}"
    FAIL
    "missing symbols: cmd_and_fixdep"
)

set(complete "${required}\ncmd_and_fixdep = true")
kontra_check_compatibility(complete "${complete}" PASS "")

set(ftrace "${complete}\nCONFIG_FUNCTION_TRACER := y")
kontra_check_compatibility(
    missing-ftrace-flags
    "${ftrace}"
    FAIL
    "missing symbols: CC_FLAGS_FTRACE"
)
kontra_check_compatibility(
    complete-ftrace
    "${ftrace}\nCC_FLAGS_FTRACE := -pg -mfentry"
    PASS
    ""
)

set(objtool "${complete}\nCONFIG_OBJTOOL := y")
kontra_check_compatibility(
    missing-conditional
    "${objtool}"
    FAIL
    "missing symbols: cmd_objtool cmd_gen_objtooldep"
)
