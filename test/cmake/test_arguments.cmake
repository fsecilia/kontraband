# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

kontra_copy_fixture(arguments source build)
set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel")
kontra_configure("${source}" "${build}" "${kernel}" Ninja)

# Exercise tokens containing semicolons through both public argument paths that preserve their contents.
set(project_root "${build}/kontra/projects/kernel")
kontra_assert_contains("${project_root}/subbuild/cmake-argument.txt" "alpha;beta\ngamma")
kontra_assert_contains("${project_root}/subbuild/optimize-dependencies.txt" "OFF")
kontra_assert_contains(
    "${project_root}/subbuild/CMakeCache.txt"
    "CMAKE_OPTIMIZE_DEPENDENCIES:BOOL=OFF"
)
set(workspace "${project_root}/modules/argument_module/Release/workspace")

# Exercise hashes as kbuild args.
string(CONCAT expected_kbuild_arguments
    [=[KONTRA_KBUILD_ARGUMENTS := 'KONTRA_TEST_ARGUMENT=alpha;beta' 'KONTRA_TEST_SECOND=gamma' ]=]
    [=['KONTRA_HASH_0=a\#b' 'KONTRA_HASH_1=a\\\#b' 'KONTRA_HASH_2=a\\\\\#b' ]=]
    [=['KONTRA_HASH_3=a\\\\\\\#b']=]
)
kontra_assert_contains_literal("${workspace}/Makefile" "${expected_kbuild_arguments}")

# Exercise hashes as compiler options.
string(CONCAT expected_compiler_options
    [=[KONTRA_CXXFLAGS_projection/kernel/argument.o += '-DKONTRA_HASH_OPTION_0=a\#b' ]=]
    [=['-DKONTRA_HASH_OPTION_1=a\\\#b' '-DKONTRA_HASH_OPTION_2=a\\\\\#b' ]=]
    [=['-DKONTRA_HASH_OPTION_3=a\\\\\\\#b']=]
)
kontra_assert_contains_literal("${workspace}/Kbuild" "${expected_compiler_options}")

# Let GNU Make parse the generated Kbuild and check that the compiler options reach the shell unchanged.
set(option_probe "${KONTRA_TEST_CASE_ROOT}/option-probe.mk")
set(option_output "${KONTRA_TEST_CASE_ROOT}/compiler-options.txt")
file(WRITE "${option_probe}"
    "obj := .\n"
    "include ${workspace}/Kbuild\n"
    ".PHONY: kontra-option-probe\n"
    "kontra-option-probe:\n"
    "\t@printf '%s\\n' $(KONTRA_CXXFLAGS_projection/kernel/argument.o) > '${option_output}'\n"
)
kontra_run(make -f "${option_probe}" kontra-option-probe)
kontra_assert_contains_literal("${option_output}" [=[-DKONTRA_HASH_OPTION_0=a#b]=])
kontra_assert_contains_literal("${option_output}" [=[-DKONTRA_HASH_OPTION_1=a\#b]=])
kontra_assert_contains_literal("${option_output}" [=[-DKONTRA_HASH_OPTION_2=a\\#b]=])
kontra_assert_contains_literal("${option_output}" [=[-DKONTRA_HASH_OPTION_3=a\\\#b]=])

kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel.argument_module)
kontra_assert_contains("${workspace}/kbuild-arguments.txt" "KONTRA_TEST_ARGUMENT=alpha;beta")
kontra_assert_contains("${workspace}/kbuild-arguments.txt" "KONTRA_TEST_SECOND=gamma")
foreach(index RANGE 0 3)
    if(index EQUAL 0)
        set(expected [=[KONTRA_HASH_0=a#b]=])
    elseif(index EQUAL 1)
        set(expected [=[KONTRA_HASH_1=a\#b]=])
    elseif(index EQUAL 2)
        set(expected [=[KONTRA_HASH_2=a\\#b]=])
    else()
        set(expected [=[KONTRA_HASH_3=a\\\#b]=])
    endif()
    kontra_assert_contains_literal("${workspace}/kbuild-arguments.txt" "${expected}")
endforeach()

set(prefix "${KONTRA_TEST_CASE_ROOT}/install")
kontra_run("${CMAKE_COMMAND}" --install "${build}" --prefix "${prefix}" --component arguments)
set(detached "${prefix}/src/arguments")
kontra_assert_contains_literal("${detached}/Makefile" "${expected_kbuild_arguments}")
file(REMOVE "${detached}/kbuild-arguments.txt")
kontra_run("${CMAKE_COMMAND}" -E chdir "${detached}" make "KERNEL_DIR=${kernel}" modules)
kontra_assert_contains("${detached}/kbuild-arguments.txt" "KONTRA_TEST_ARGUMENT=alpha;beta")
kontra_assert_contains("${detached}/kbuild-arguments.txt" "KONTRA_TEST_SECOND=gamma")
kontra_assert_contains_literal("${detached}/kbuild-arguments.txt" [=[KONTRA_HASH_0=a#b]=])
kontra_assert_contains_literal("${detached}/kbuild-arguments.txt" [=[KONTRA_HASH_1=a\#b]=])
kontra_assert_contains_literal("${detached}/kbuild-arguments.txt" [=[KONTRA_HASH_2=a\\#b]=])
kontra_assert_contains_literal("${detached}/kbuild-arguments.txt" [=[KONTRA_HASH_3=a\\\#b]=])

# Kontraband disables dependency optimization by default because projection uses CMake's dependency graph. An explicit
# nested cache argument remains ordinary project input and may override that default.
set(optimized_build "${KONTRA_TEST_CASE_ROOT}/optimized-build")
kontra_run(
    "${CMAKE_COMMAND}" -S "${source}" -B "${optimized_build}" -G Ninja
    "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
    "-DFIXTURE_KERNEL_DIR=${kernel}"
    "-DFIXTURE_OPTIMIZE_DEPENDENCIES=ON"
    "-DCMAKE_BUILD_TYPE=Release"
)
kontra_assert_contains(
    "${optimized_build}/kontra/projects/kernel/subbuild/optimize-dependencies.txt"
    "ON"
)
kontra_assert_contains(
    "${optimized_build}/kontra/projects/kernel/subbuild/CMakeCache.txt"
    "CMAKE_OPTIMIZE_DEPENDENCIES:BOOL=ON"
)

# Errors must show the exact token that made the generated Make syntax unsafe.
set(diagnostic_script "${KONTRA_TEST_CASE_ROOT}/diagnostic-semicolons.cmake")
file(WRITE "${diagnostic_script}" [=[
include("@PREFIX@/share/cmake/kontraband/detail/arguments.cmake")
if(CASE STREQUAL "compiler")
    _kontra_quote_shell_argument("-DBROKEN=alpha;beta" "compile definition" ignored)
elseif(CASE STREQUAL "kbuild")
    set(argument "BROKEN=alpha;beta\nsecond-line")
    _kontra_quote_kbuild_argument("${argument}" ignored)
else()
    message(FATAL_ERROR "unknown CASE")
endif()
]=])
file(READ "${diagnostic_script}" diagnostic_source)
string(REPLACE "@PREFIX@" "${KONTRA_TEST_PREFIX}" diagnostic_source "${diagnostic_source}")
file(WRITE "${diagnostic_script}" "${diagnostic_source}")
function(kontra_expect_argument_diagnostic case expected_id expected_text)
    execute_process(
        COMMAND "${CMAKE_COMMAND}" "-DCASE=${case}" -P "${diagnostic_script}"
        RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error
    )
    set(log "${output}${error}")
    if(result EQUAL 0 OR
       NOT log MATCHES "Kontraband\\[${expected_id}\\]:" OR
       NOT log MATCHES "${expected_text}")
        message(FATAL_ERROR "${case} diagnostic did not preserve its token containing a semicolon:\n${log}")
    endif()
endfunction()
kontra_expect_argument_diagnostic(compiler unsupported-compiler-argument "-DBROKEN=alpha;beta")
kontra_expect_argument_diagnostic(kbuild unsupported-kbuild-argument "BROKEN=alpha;beta")
