# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

# Public commands should reject bad arguments before nested configuration or generated build steps can run.
kontra_failure_outer(missing_module_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(missing_module PROJECT kernel)
]=])
kontra_expect_configure_failure(
    missing-module
    missing-module-target
    "${missing_module_outer}"
    "${valid_nested}"
)

kontra_failure_outer(invalid_argument_outer [=[
kontra_add_kernel_project(kernel
    KERNEL_BUILD_DIRECTORY "@KERNEL@"
    CMAKE_ARGUMENTS --toolchain toolchain.cmake
)
]=])
kontra_expect_configure_failure(
    invalid-argument
    invalid-nested-cmake-argument
    "${invalid_argument_outer}"
    "${valid_nested}"
)

kontra_failure_outer(split_argument_outer [=[
kontra_add_kernel_project(kernel
    KERNEL_BUILD_DIRECTORY "@KERNEL@"
    CMAKE_ARGUMENTS "-D" "EXAMPLE_FEATURE=ON"
)
]=])
kontra_expect_configure_failure(
    split-argument
    invalid-nested-cmake-argument
    "${split_argument_outer}"
    "${valid_nested}"
)

kontra_failure_outer(unsafe_argument_outer [=[
kontra_add_kernel_project(kernel
    KERNEL_BUILD_DIRECTORY "@KERNEL@"
    CMAKE_ARGUMENTS "-DCMAKE_CXX_FLAGS=-O3"
)
]=])
kontra_expect_configure_failure(
    unsafe-argument
    unsafe-nested-cmake-argument
    "${unsafe_argument_outer}"
    "${valid_nested}"
)

# These nested project/compiler hooks can change which languages are enabled before Kontraband reads the File API.
# Kontraband sets them itself even though CMake accepts them as ordinary -D cache entries.
foreach(owned_argument IN ITEMS
    "CMAKE_CXX_COMPILER_LAUNCHER=ccache"
    "CMAKE_PROJECT_TOP_LEVEL_INCLUDES=hook.cmake"
    "CMAKE_PROJECT_INCLUDE=hook.cmake"
    "CMAKE_PROJECT_INCLUDE_BEFORE=hook.cmake"
    "CMAKE_PROJECT_example_INCLUDE=hook.cmake"
    "CMAKE_PROJECT_example_INCLUDE_BEFORE=hook.cmake"
    "CMAKE_SYSTEM_NAME=Linux"
    "CMAKE_SYSTEM_PROCESSOR=aarch64"
    "CMAKE_CROSSCOMPILING=FALSE"
    "CMAKE_USER_MAKE_RULES_OVERRIDE=hook.cmake"
    "CMAKE_USER_MAKE_RULES_OVERRIDE_CXX=hook.cmake"
)
    kontra_failure_outer(owned_setup_argument_outer [=[
kontra_add_kernel_project(
    kernel
    KERNEL_BUILD_DIRECTORY "@KERNEL@"
    CMAKE_ARGUMENTS "-D@OWNED_ARGUMENT@"
)
]=])
    string(REPLACE "@OWNED_ARGUMENT@" "${owned_argument}" owned_setup_argument_outer "${owned_setup_argument_outer}")
    string(REGEX REPLACE "[^A-Za-z0-9]+" "-" case_name "${owned_argument}")
    kontra_expect_configure_failure(
        "owned-nested-setup-${case_name}"
        unsafe-nested-cmake-argument
        "${owned_setup_argument_outer}"
        "${valid_nested}"
    )
endforeach()

kontra_failure_outer(invalid_output_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(other PROJECT kernel OUTPUT_NAME invalid.name)
]=])
kontra_expect_configure_failure(invalid-output invalid-module-output-name "${invalid_output_outer}" "${valid_nested}")

# Package and generated target names must not collide with names the caller already uses. Reject collisions during
# configure instead of depending on what a particular generator does later.
kontra_failure_outer(version_outer [=[
set(KONTRA_ENTRY_VERSION 9.9.9)
include("@PREFIX@/share/cmake/kontraband/kontraband.cmake")
]=])
kontra_expect_configure_failure(version-conflict version-conflict "${version_outer}" "${valid_nested}")

kontra_failure_outer(aggregate_project_name_outer [=[
kontra_add_kernel_project(kontra_kernel_modules KERNEL_BUILD_DIRECTORY "@KERNEL@")
]=])
kontra_expect_configure_failure(
    aggregate-project-name
    invalid-name
    "${aggregate_project_name_outer}"
    "${valid_nested}"
)

# Test two collisions through the public API: one ordinary generated target and one GNU Make special target. The full
# denylist below calls the private validator directly so every spelling does not need a complete configure/generate run.
foreach(reserved_name IN ITEMS all .WAIT)
    kontra_failure_outer(reserved_project_name_outer [=[
kontra_add_kernel_project(@RESERVED_NAME@ KERNEL_BUILD_DIRECTORY "@KERNEL@")
]=])
    string(REPLACE "@RESERVED_NAME@" "${reserved_name}" reserved_project_name_outer "${reserved_project_name_outer}")
    kontra_expect_configure_failure(
        "reserved-project-name-public-${reserved_name}"
        invalid-name
        "${reserved_project_name_outer}"
        "${valid_nested}"
    )
endforeach()

foreach(reserved_name IN ITEMS
    build.ninja clean CMakeCache.txt cmake_check_build_system default_target depend edit_cache help install package
    package_source preinstall rebuild_cache test .DEFAULT .DELETE_ON_ERROR .EXPORT_ALL_VARIABLES .IGNORE .INTERMEDIATE
    .LOW_RESOLUTION_TIME .NOTINTERMEDIATE .NOTPARALLEL .ONESHELL .PHONY .POSIX .PRECIOUS .SECONDARY .SECONDEXPANSION
    .SILENT .SUFFIXES
    kontra_kernel_modules kontra_kernel_modules.unchecked kontra_kernel_modules.clean
)
    set(reserved_name_body [=[
cmake_minimum_required(VERSION 3.31.6)
include("@PREFIX@/share/cmake/kontraband/detail/common.cmake")
_kontra_validate_kernel_project_name("@RESERVED_NAME@")
]=])
    string(REPLACE "@RESERVED_NAME@" "${reserved_name}" reserved_name_body "${reserved_name_body}")
    kontra_expect_script_failure("reserved-project-name-${reserved_name}" invalid-name "${reserved_name_body}")
endforeach()

# A keyword with no value is different from an optional keyword that was omitted. Test each public parser with empty,
# false-looking, and missing values so cmake_parse_arguments() cannot hide them.
kontra_failure_outer(missing_project_value_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@" DIRECTORY)
]=])
kontra_expect_configure_failure(
    missing-project-keyword-value
    missing-keyword-value
    "${missing_project_value_outer}"
    "${valid_nested}"
)

kontra_failure_outer(missing_module_value_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(other PROJECT kernel OUTPUT_NAME)
]=])
kontra_expect_configure_failure(
    missing-module-keyword-value
    missing-keyword-value
    "${missing_module_value_outer}"
    "${valid_nested}"
)

kontra_failure_outer(missing_module_install_value_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(other PROJECT kernel)
kontra_install_kernel_module(kernel.other DESTINATION share/module COMPONENT)
]=])
kontra_expect_configure_failure(
    missing-module-install-keyword-value
    missing-keyword-value
    "${missing_module_install_value_outer}"
    "${valid_nested}"
)

kontra_failure_outer(missing_project_install_value_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(other PROJECT kernel)
kontra_install_kernel_project(kernel DESTINATION share/project COMPONENT)
]=])
kontra_expect_configure_failure(
    missing-project-install-keyword-value
    missing-keyword-value
    "${missing_project_install_value_outer}"
    "${valid_nested}"
)

# All global aggregates use the same collision check, so one public case is enough here.
kontra_failure_outer(aggregate_collision_outer [=[
add_custom_target(kontra_kernel_modules)
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
]=])
kontra_expect_configure_failure(
    aggregate-collision
    target-already-exists
    "${aggregate_collision_outer}"
    "${valid_nested}"
)

kontra_failure_outer(project_clean_collision_outer [=[
add_custom_target(kernel.clean)
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
]=])
kontra_expect_configure_failure(
    project-clean-collision
    target-already-exists
    "${project_clean_collision_outer}"
    "${valid_nested}"
)

# cmake_parse_arguments() can make false-looking tokens easy to mishandle. OFF is still an unexpected positional
# argument.
kontra_failure_outer(false_unparsed_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@" OFF)
]=])
kontra_expect_configure_failure(
    false-valued-unparsed-argument
    invalid-arguments
    "${false_unparsed_outer}"
    "${valid_nested}"
)

# Public commands report missing targets, ordinary CMake targets, and wrong Kontraband target types separately. They
# also report a missing project file before trying nested configuration.
kontra_failure_outer(missing_target_outer [=[
kontra_install_kernel_module(missing DESTINATION share/module)
]=])
kontra_expect_configure_failure(
    missing-target
    missing-target
    "${missing_target_outer}"
    "${valid_nested}"
)

kontra_failure_outer(not_kernel_project_outer [=[
add_custom_target(ordinary)
kontra_add_kernel_module(other PROJECT ordinary)
]=])
kontra_expect_configure_failure(
    not-a-kernel-project
    not-a-kernel-project
    "${not_kernel_project_outer}"
    "${valid_nested}"
)

kontra_failure_outer(not_kernel_module_outer [=[
add_custom_target(ordinary)
kontra_install_kernel_module(ordinary DESTINATION share/module)
]=])
kontra_expect_configure_failure(
    not-a-kernel-module
    not-a-kernel-module
    "${not_kernel_module_outer}"
    "${valid_nested}"
)

kontra_failure_outer(missing_kernel_project_outer [=[
kontra_add_kernel_project(kernel DIRECTORY missing KERNEL_BUILD_DIRECTORY "@KERNEL@")
]=])
kontra_expect_configure_failure(
    missing-kernel-project
    missing-kernel-project
    "${missing_kernel_project_outer}"
    "${valid_nested}"
)

kontra_failure_outer(missing_projection_root_outer [=[
kontra_add_kernel_project(kernel PROJECTION_ROOT missing KERNEL_BUILD_DIRECTORY "@KERNEL@")
]=])
kontra_expect_configure_failure(
    missing-projection-root
    missing-projection-root
    "${missing_projection_root_outer}"
    "${valid_nested}"
)

kontra_failure_outer(missing_kbuild_include_outer [=[
kontra_add_kernel_project(kernel KBUILD_INCLUDE missing.kbuild KERNEL_BUILD_DIRECTORY "@KERNEL@")
]=])
kontra_expect_configure_failure(
    missing-kbuild-include
    missing-kbuild-include
    "${missing_kbuild_include_outer}"
    "${valid_nested}"
)
