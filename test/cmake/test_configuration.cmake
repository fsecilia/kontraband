# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")
file(REMOVE_RECURSE "${KONTRA_TEST_CASE_ROOT}")
set(source "${KONTRA_TEST_CASE_ROOT}/source")
set(build "${KONTRA_TEST_CASE_ROOT}/build")
file(MAKE_DIRECTORY "${source}/kernel")
file(WRITE "${source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(configuration LANGUAGES NONE)
find_package(kontraband CONFIG REQUIRED)
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(module PROJECT kernel)
]=])
file(READ "${source}/CMakeLists.txt" outer)
string(REPLACE "@KERNEL@" "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel" outer "${outer}")
file(WRITE "${source}/CMakeLists.txt" "${outer}")
file(WRITE "${source}/kernel/module.cpp" "// SPDX-License-Identifier: MIT\n")
file(WRITE "${source}/kernel/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(configuration_kernel LANGUAGES CXX)
add_library(module OBJECT module.cpp)
target_compile_definitions(module PRIVATE
    "$<$<CONFIG:Release>:EXPLICIT_RELEASE_CONFIGURATION>"
    "$<$<CONFIG:Debug>:EXPLICIT_DEBUG_CONFIGURATION>"
)
]=])

# Do not use kontra_configure(): this test intentionally leaves CMAKE_BUILD_TYPE empty.
kontra_run(
    "${CMAKE_COMMAND}" -S "${source}" -B "${build}" -G Ninja
    "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
)
set(nested_cache "${build}/kontra/projects/kernel/subbuild/CMakeCache.txt")
file(STRINGS "${nested_cache}" build_type_lines REGEX "^CMAKE_BUILD_TYPE:STRING=")
if(NOT build_type_lines STREQUAL "CMAKE_BUILD_TYPE:STRING=")
    message(FATAL_ERROR "nested empty CMAKE_BUILD_TYPE was not preserved: ${build_type_lines}")
endif()
set(kbuild "${build}/kontra/projects/kernel/modules/module/default/workspace/Kbuild")
kontra_assert_exists("${kbuild}")
kontra_assert_not_contains("${kbuild}" "EXPLICIT_RELEASE_CONFIGURATION")
kontra_assert_not_contains("${kbuild}" "EXPLICIT_DEBUG_CONFIGURATION")
kontra_assert_not_contains("${kbuild}" "NDEBUG")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel.module.unchecked)

# An explicit configuration is normal CMake input and should resolve normally.
set(release_build "${KONTRA_TEST_CASE_ROOT}/release-build")
kontra_configure("${source}" "${release_build}" "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel" Ninja)
kontra_assert_contains(
    "${release_build}/kontra/projects/kernel/modules/module/Release/workspace/Kbuild"
    "EXPLICIT_RELEASE_CONFIGURATION"
)
if(KONTRA_LAST_OUTPUT MATCHES "unattributed compiler option")
    message(FATAL_ERROR "ordinary Release compiler baseline produced a discard diagnostic:
${KONTRA_LAST_OUTPUT}")
endif()

# Configuration names become path components, not target names. Non-ASCII names are valid as long as any ASCII bytes
# in them are safe for Make.
set(unicode_build "${KONTRA_TEST_CASE_ROOT}/unicode-build")
kontra_run(
    "${CMAKE_COMMAND}" -S "${source}" -B "${unicode_build}" -G Ninja
    "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
    "-DCMAKE_BUILD_TYPE=Débogage"
)
set(unicode_kbuild "${unicode_build}/kontra/projects/kernel/modules/module/Débogage/workspace/Kbuild")
kontra_assert_exists("${unicode_kbuild}")
kontra_run("${CMAKE_COMMAND}" --build "${unicode_build}" --target kernel.module.unchecked)

# CMake adds some compiler flags while each nested language is enabled. Record those initial flags so Kontraband can
# remove them from the exported options. Changes made later through global flag variables are different: they have no
# target attribution and remain unsupported. Match repeated flags by occurrence, not just by value.
set(baseline_source "${KONTRA_TEST_CASE_ROOT}/baseline-source")
set(baseline_build "${KONTRA_TEST_CASE_ROOT}/baseline-build")
file(MAKE_DIRECTORY "${baseline_source}/kernel")
set(poison_toolchain "${baseline_source}/poison-toolchain.cmake")
file(WRITE "${poison_toolchain}" "message(FATAL_ERROR \"ambient toolchain file reached nested CMake\")\n")
set(launcher "${baseline_source}/kontra-test-launcher.sh")
set(launcher_log "${baseline_source}/launcher.log")
file(WRITE "${launcher}" "#!/bin/sh\nprintf '%s\\n' \"$*\" >> '${launcher_log}'\nexec \"$@\"\n")
file(CHMOD "${launcher}"
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
)
file(WRITE "${baseline_source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(configuration_baseline LANGUAGES NONE)
find_package(kontraband CONFIG REQUIRED)
set(ENV{CMAKE_TOOLCHAIN_FILE} "@POISON_TOOLCHAIN@")
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(module PROJECT kernel)
]=])
file(READ "${baseline_source}/CMakeLists.txt" baseline_outer)
string(REPLACE "@KERNEL@" "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel" baseline_outer "${baseline_outer}")
string(REPLACE "@POISON_TOOLCHAIN@" "${poison_toolchain}" baseline_outer "${baseline_outer}")
file(WRITE "${baseline_source}/CMakeLists.txt" "${baseline_outer}")
file(WRITE "${baseline_source}/kernel/a.c" "int a;\n")
file(WRITE "${baseline_source}/kernel/b.c" "int b;\n")
file(WRITE "${baseline_source}/kernel/cxx.cpp" "int cxx;\n")
file(WRITE "${baseline_source}/kernel/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
set(CMAKE_C_FLAGS_DEBUG_INIT "-DKONTRA_INIT_ONLY=1 -DKONTRA_BASELINE_DUPLICATE=1")
project(configuration_baseline_kernel LANGUAGES NONE)
foreach(environment_name IN ITEMS CFLAGS CXXFLAGS ASMFLAGS LDFLAGS)
    if(DEFINED ENV{${environment_name}})
        message(FATAL_ERROR "ambient ${environment_name} reached nested CMake")
    endif()
endforeach()
enable_language(C)
enable_language(CXX)
set(CMAKE_C_FLAGS_DEBUG
    "${CMAKE_C_FLAGS_DEBUG} -DKONTRA_BASELINE_DUPLICATE=1 -DKONTRA_EXTRA_GLOBAL=1"
)
add_library(module OBJECT a.c b.c cxx.cpp)
set_property(SOURCE b.c TARGET_DIRECTORY module APPEND PROPERTY COMPILE_DEFINITIONS KONTRA_SPLIT_GROUP=1)
]=])
kontra_run(
    "${CMAKE_COMMAND}" -E env
    "CFLAGS=-DKONTRA_ENV_C=1"
    "CXXFLAGS=-DKONTRA_ENV_CXX=1"
    "ASMFLAGS=-DKONTRA_ENV_ASM=1"
    "LDFLAGS=-Wl,--defsym,KONTRA_ENV_LINK=1"
    "CMAKE_C_COMPILER_LAUNCHER=${launcher}"
    "CMAKE_CXX_COMPILER_LAUNCHER=${launcher}"
    "${CMAKE_COMMAND}"
    -S "${baseline_source}" -B "${baseline_build}" -G Ninja
    "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
    "-DCMAKE_BUILD_TYPE=Debug"
)
if(KONTRA_LAST_OUTPUT MATCHES "'-g'" OR
   KONTRA_LAST_OUTPUT MATCHES "'-DKONTRA_INIT_ONLY=1'")
    message(FATAL_ERROR "nested initialized compiler baseline was reported as an unsupported option:\n${KONTRA_LAST_OUTPUT}")
endif()
kontra_assert_exists("${launcher_log}")
kontra_assert_contains("${launcher_log}" "cc")
set(baseline_kbuild "${baseline_build}/kontra/projects/kernel/modules/module/Debug/workspace/Kbuild")
kontra_assert_not_contains("${baseline_kbuild}" "kontra-test-launcher")
string(REGEX MATCHALL
    "'-DKONTRA_BASELINE_DUPLICATE=1'"
    duplicate_messages
    "${KONTRA_LAST_OUTPUT}"
)
string(REGEX MATCHALL
    "'-DKONTRA_EXTRA_GLOBAL=1'"
    extra_messages
    "${KONTRA_LAST_OUTPUT}"
)
list(LENGTH duplicate_messages duplicate_message_count)
list(LENGTH extra_messages extra_message_count)
if(NOT duplicate_message_count EQUAL 1 OR NOT extra_message_count EQUAL 1)
    message(FATAL_ERROR "unexpected unattributed options were not reported exactly once each:\n${KONTRA_LAST_OUTPUT}")
endif()
if(NOT KONTRA_LAST_OUTPUT MATCHES "'-DKONTRA_BASELINE_DUPLICATE=1' \\(2 occurrences\\)" OR
   NOT KONTRA_LAST_OUTPUT MATCHES "'-DKONTRA_EXTRA_GLOBAL=1' \\(2 occurrences\\)" OR
   NOT KONTRA_LAST_OUTPUT MATCHES "Kontraband\\[unprojected-compiler-option\\]" OR
   NOT KONTRA_LAST_OUTPUT MATCHES "will not be used when the kernel module is compiled")
    message(FATAL_ERROR "discard warning did not report the unexpected options and occurrence counts:\n${KONTRA_LAST_OUTPUT}")
endif()

# A false-looking token is still a real compiler option and must not hide the warning about unattributed flags.
set(false_option_source "${KONTRA_TEST_CASE_ROOT}/false-option-source")
set(false_option_build "${KONTRA_TEST_CASE_ROOT}/false-option-build")
file(MAKE_DIRECTORY "${false_option_source}/kernel")
file(WRITE "${false_option_source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(configuration_false_option LANGUAGES NONE)
find_package(kontraband CONFIG REQUIRED)
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(module PROJECT kernel)
]=])
file(READ "${false_option_source}/CMakeLists.txt" false_option_outer)
string(REPLACE "@KERNEL@" "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel" false_option_outer "${false_option_outer}")
file(WRITE "${false_option_source}/CMakeLists.txt" "${false_option_outer}")
file(WRITE "${false_option_source}/kernel/module.cpp" "int module;\n")
file(WRITE "${false_option_source}/kernel/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(configuration_false_option_kernel LANGUAGES CXX)
set(CMAKE_CXX_FLAGS "0")
add_library(module OBJECT module.cpp)
]=])
kontra_run(
    "${CMAKE_COMMAND}" -S "${false_option_source}" -B "${false_option_build}" -G Ninja
    "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
)
if(NOT KONTRA_LAST_OUTPUT MATCHES "Kontraband\\[unprojected-compiler-option\\]" OR
   NOT KONTRA_LAST_OUTPUT MATCHES "'0'")
    message(FATAL_ERROR "false-valued unattributed option did not produce the discard warning:\n${KONTRA_LAST_OUTPUT}")
endif()

# Keep stderr from a successful nested configure visible because CMake can report lost information there, such as a
# definition containing '#'. Hide routine STATUS output unless VERBOSE is enabled.
set(diagnostic_source "${KONTRA_TEST_CASE_ROOT}/diagnostic-source")
set(diagnostic_build "${KONTRA_TEST_CASE_ROOT}/diagnostic-build")
file(MAKE_DIRECTORY "${diagnostic_source}/kernel")
file(WRITE "${diagnostic_source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(configuration_diagnostics LANGUAGES NONE)
find_package(kontraband CONFIG REQUIRED)
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
]=])
file(READ "${diagnostic_source}/CMakeLists.txt" diagnostic_outer)
string(REPLACE "@KERNEL@" "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel" diagnostic_outer "${diagnostic_outer}")
file(WRITE "${diagnostic_source}/CMakeLists.txt" "${diagnostic_outer}")
file(WRITE "${diagnostic_source}/kernel/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(configuration_diagnostics_kernel LANGUAGES C)
message(STATUS "KONTRA_NESTED_STATUS_SENTINEL")
message(WARNING "KONTRA_NESTED_WARNING_SENTINEL")
]=])
kontra_run(
    "${CMAKE_COMMAND}" -S "${diagnostic_source}" -B "${diagnostic_build}" -G Ninja
    "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
)
if(NOT KONTRA_LAST_OUTPUT MATCHES "KONTRA_NESTED_WARNING_SENTINEL")
    message(FATAL_ERROR "successful nested warning was hidden:\n${KONTRA_LAST_OUTPUT}")
endif()
if(KONTRA_LAST_OUTPUT MATCHES "KONTRA_NESTED_STATUS_SENTINEL")
    message(FATAL_ERROR "routine nested status output was not verbose-only:\n${KONTRA_LAST_OUTPUT}")
endif()

# VERBOSE shows the hidden STATUS output; warnings stay visible either way.
set(verbose_build "${KONTRA_TEST_CASE_ROOT}/diagnostic-verbose-build")
kontra_run(
    "${CMAKE_COMMAND}" --log-level=VERBOSE
    -S "${diagnostic_source}" -B "${verbose_build}" -G Ninja
    "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
)
if(NOT KONTRA_LAST_OUTPUT MATCHES "KONTRA_NESTED_STATUS_SENTINEL")
    message(FATAL_ERROR "verbose configure omitted nested status output:\n${KONTRA_LAST_OUTPUT}")
endif()
