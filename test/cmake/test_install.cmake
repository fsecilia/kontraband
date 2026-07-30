# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")
kontra_copy_fixture(project source build)
set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel")

# A declared source symlink stays a symlink in the development workspace, but installation must copy the file it
# points to.
file(WRITE "${source}/include/fixture/symlink-target.hpp" "#pragma once\n#define FIXTURE_SYMLINK_TARGET 1\n")
file(CREATE_LINK
    "${source}/include/fixture/symlink-target.hpp"
    "${source}/include/fixture/symlink.hpp"
    SYMBOLIC
)
file(READ "${source}/config.cmake" config)
string(REPLACE
    [=["${root}/include/fixture/core.hpp"]=]
    [=["${root}/include/fixture/core.hpp"
        "${root}/include/fixture/symlink.hpp"]=]
    config "${config}"
)
file(WRITE "${source}/config.cmake" "${config}")

# An include directory with no projected files should still affect Kbuild flags. It should not create different
# directory contents between the development and installed projections.
file(MAKE_DIRECTORY "${source}/empty-include")
file(APPEND "${source}/kernel/CMakeLists.txt" [=[
target_include_directories(fixture_module PRIVATE "${CMAKE_CURRENT_LIST_DIR}/../empty-include")
]=])

kontra_configure("${source}" "${build}" "${kernel}" Ninja)

# Separate install rules for the same module need separate staging directories. Otherwise concurrent component installs
# could delete or refill each other's temporary trees.
set(install_script "${build}/cmake_install.cmake")
kontra_assert_contains("${install_script}" "modules/fixture_module/install/default/0")
kontra_assert_contains("${install_script}" "modules/fixture_module/install/default/1")

set(workspace "${build}/kontra/projects/kernel_project/modules/fixture_module/Release/workspace")
kontra_assert_contains("${workspace}/Kbuild" "-I\\$\\(src\\)/projection/empty-include")
if(EXISTS "${workspace}/projection/empty-include")
    message(FATAL_ERROR "development projection materialized a fileless include directory")
endif()
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module.unchecked)

# Separate components can install concurrently to different prefixes without sharing a staging directory.
set(concurrent_module_prefix "${KONTRA_TEST_CASE_ROOT}/concurrent-module")
set(concurrent_all_prefix "${KONTRA_TEST_CASE_ROOT}/concurrent-all")
set(concurrent_script "${KONTRA_TEST_CASE_ROOT}/concurrent-install.sh")
file(WRITE "${concurrent_script}"
    "#!/bin/sh\n"
    "set -eu\n"
    "\"${CMAKE_COMMAND}\" --install \"${build}\" --prefix \"${concurrent_module_prefix}\" --component dkms-module &\n"
    "first=$!\n"
    "\"${CMAKE_COMMAND}\" --install \"${build}\" --prefix \"${concurrent_all_prefix}\" --component dkms-all &\n"
    "second=$!\n"
    "wait \"$first\"\n"
    "wait \"$second\"\n"
)
kontra_run(/bin/sh "${concurrent_script}")
kontra_assert_exists("${concurrent_module_prefix}/src/fixture-1.2.3/Kbuild")
kontra_assert_exists("${concurrent_all_prefix}/share/fixture/modules/fixture_output/Kbuild")
kontra_assert_exists("${concurrent_all_prefix}/share/fixture/modules/fixture_aux/Kbuild")

# Installation copies the currently declared sources directly. Editing a source file must not require rebuilding the
# module before install.
file(APPEND "${source}/kernel/bridge_impl.cpp" "\n// changed after module build, before install\n")
set(module_prefix "${KONTRA_TEST_CASE_ROOT}/module-install")
kontra_run("${CMAKE_COMMAND}" --install "${build}" --prefix "${module_prefix}" --component dkms-module)
set(module_root "${module_prefix}/src/fixture-1.2.3")
kontra_assert_exists("${module_root}/Kbuild")
kontra_assert_exists("${module_root}/Makefile")
kontra_assert_contains("${module_root}/projection/kernel/bridge_impl.cpp" "changed after module build, before install")
kontra_assert_exists("${module_root}/kontra-user.kbuild")
if(EXISTS "${module_root}/projection/empty-include")
    message(FATAL_ERROR "installed projection materialized a fileless include directory")
endif()
kontra_assert_contains("${module_root}/projection/include/fixture/symlink.hpp" "FIXTURE_SYMLINK_TARGET")
if(IS_SYMLINK "${module_root}/projection/include/fixture/symlink.hpp")
    message(FATAL_ERROR "installed declared source symlink was not dereferenced")
endif()

file(GLOB_RECURSE forbidden
    "${module_root}/*.cmake"
    "${module_root}/*.json"
    "${module_root}/*.files"
    "${module_root}/*.ko"
    "${module_root}/*.o"
)
if(forbidden)
    message(FATAL_ERROR "installed projection contains private/build artifacts: ${forbidden}")
endif()

execute_process(
    COMMAND stat -c %a "${module_root}/projection/include/fixture/executable_helper.sh"
    RESULT_VARIABLE stat_result OUTPUT_VARIABLE mode OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT stat_result EQUAL 0 OR NOT mode MATCHES "[1357]$")
    message(FATAL_ERROR "executable support-file permission was not preserved: ${mode}")
endif()
kontra_assert_contains("${build}/install_manifest_dkms-module.txt" "projection/kernel/bridge_impl.cpp")
kontra_assert_contains("${module_root}/Makefile" ".PHONY: default modules modules_install clean")
kontra_assert_not_contains("${module_root}/Makefile" "KERNEL_RELEASE")
kontra_assert_not_contains("${module_root}/Makefile" "KVER")
kontra_assert_not_contains("${module_root}/Makefile" "INSTALL_MOD_STRIP=1")
kontra_assert_not_contains("${module_root}/Makefile" "install: modules_install")

kontra_run("${CMAKE_COMMAND}" -E chdir "${module_root}" make
    "KERNEL_DIR=${kernel}" modules)
kontra_assert_exists("${module_root}/fixture_output.ko")

# modules_install passes through to Kbuild. Install options supplied on the Make command line must reach the recursive
# Kbuild invocation unchanged.
set(install_root "${KONTRA_TEST_CASE_ROOT}/install-root")
kontra_run("${CMAKE_COMMAND}" -E chdir "${module_root}" make
    "KERNEL_DIR=${kernel}"
    "INSTALL_MOD_PATH=${install_root}"
    "INSTALL_MOD_STRIP=1"
    modules_install
)
kontra_assert_contains_literal("${module_root}/kbuild-install-arguments.txt" "INSTALL_MOD_PATH=${install_root}")
kontra_assert_contains("${module_root}/kbuild-install-arguments.txt" "INSTALL_MOD_STRIP=1")

# An installed wrapper can build against a different prepared kernel. Check the linker selected by that Kbuild instead
# of assuming it matches the linker seen during configure.
set(detached_kernel "${KONTRA_TEST_CASE_ROOT}/detached-kernel")
file(REMOVE_RECURSE "${detached_kernel}")
file(COPY "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel/" DESTINATION "${detached_kernel}")
file(WRITE "${detached_kernel}/include/config/auto.conf"
    "CONFIG_CC_IS_CLANG=n\nCONFIG_LD_IS_LLD=y\n"
)
set(bad_linker_bin "${KONTRA_TEST_CASE_ROOT}/bad-linker-bin")
file(MAKE_DIRECTORY "${bad_linker_bin}")
file(WRITE "${bad_linker_bin}/ld.lld" "#!/bin/sh\nexit 1\n")
file(CHMOD "${bad_linker_bin}/ld.lld" PERMISSIONS
    OWNER_READ OWNER_WRITE OWNER_EXECUTE
    GROUP_READ GROUP_EXECUTE
    WORLD_READ WORLD_EXECUTE
)
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env "PATH=${bad_linker_bin}:$ENV{PATH}"
        make -C "${module_root}" "KERNEL_DIR=${detached_kernel}" modules
    RESULT_VARIABLE detached_link_result
    OUTPUT_VARIABLE detached_link_output
    ERROR_VARIABLE detached_link_error
)
if(detached_link_result EQUAL 0 OR
   NOT "${detached_link_output}${detached_link_error}" MATCHES "Kontraband\\[unsupported-linker\\]")
    message(FATAL_ERROR
        "detached build did not reject the linker selected by its current kernel:\n"
        "${detached_link_output}${detached_link_error}"
    )
endif()
kontra_run(
    "${CMAKE_COMMAND}" -E env "PATH=${bad_linker_bin}:$ENV{PATH}"
    make -C "${module_root}" "KERNEL_DIR=${detached_kernel}" clean
)

set(all_prefix "${KONTRA_TEST_CASE_ROOT}/all-install")
kontra_run("${CMAKE_COMMAND}" --install "${build}" --prefix "${all_prefix}" --component dkms-all)
kontra_assert_exists("${all_prefix}/share/fixture/modules/fixture_output/Kbuild")
kontra_assert_exists("${all_prefix}/share/fixture/modules/fixture_aux/Kbuild")
