# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

if(NOT DEFINED KONTRA_ENTRY_VERSION OR KONTRA_ENTRY_VERSION STREQUAL "")
    message(FATAL_ERROR "Kontraband[missing-package-version]: public entry point was loaded without its package version")
endif()

get_property(kontra_loaded_version GLOBAL PROPERTY KONTRA_LOADED_VERSION)
if(kontra_loaded_version)
    if(NOT kontra_loaded_version STREQUAL KONTRA_ENTRY_VERSION)
        message(FATAL_ERROR
            "Kontraband[version-conflict]: version ${KONTRA_ENTRY_VERSION} was loaded after "
            "version ${kontra_loaded_version}; one enclosing build cannot use multiple Kontraband versions"
        )
    endif()
    unset(kontra_loaded_version)
    return()
endif()

include("${CMAKE_CURRENT_LIST_DIR}/detail/project.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/detail/module.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/detail/install.cmake")

set(
    KONTRA_KBUILD_VERBOSE
    OFF
    CACHE BOOL
    "show verbose Kbuild commands for Kontraband development builds"
)

#
# Public API
#

# Declares and configures one nested CMake project that can export kernel modules.
function(kontra_add_kernel_project project_name)
    set(options)
    set(one_value_args DIRECTORY PROJECTION_ROOT KERNEL_BUILD_DIRECTORY KBUILD_INCLUDE)
    set(multi_value_args CMAKE_PREFIX_PATH CMAKE_ARGUMENTS KBUILD_ARGUMENTS)
    cmake_parse_arguments(PARSE_ARGV 1 args "${options}" "${one_value_args}" "${multi_value_args}")
    _kontra_require_complete_arguments("kontra_add_kernel_project" "${args_KEYWORDS_MISSING_VALUES}")
    if(NOT "${args_UNPARSED_ARGUMENTS}" STREQUAL "" OR project_name STREQUAL "")
        _kontra_fail(
            invalid-arguments
            "kontra_add_kernel_project() requires a project name"
        )
    endif()
    _kontra_validate_kernel_project_name("${project_name}")
    _kontra_validate_nested_arguments("${args_CMAKE_ARGUMENTS}")
    if(TARGET "${project_name}" OR TARGET "${project_name}.unchecked" OR TARGET "${project_name}.clean")
        _kontra_fail(
            target-already-exists
            "outer target '${project_name}', '${project_name}.unchecked', or '${project_name}.clean' already exists"
        )
    endif()

    _kontra_add_kernel_project(
        "${project_name}"
        "${args_DIRECTORY}"
        "${args_PROJECTION_ROOT}"
        "${args_KERNEL_BUILD_DIRECTORY}"
        "${args_KBUILD_INCLUDE}"
        "${args_CMAKE_PREFIX_PATH}"
        "${args_CMAKE_ARGUMENTS}"
        "${args_KBUILD_ARGUMENTS}"
    )
endfunction()

# Exports one nested OBJECT_LIBRARY target as a Kbuild module and creates its outer CMake targets.
function(kontra_add_kernel_module module)
    set(options)
    set(one_value_args PROJECT OUTPUT_NAME)
    cmake_parse_arguments(PARSE_ARGV 1 args "${options}" "${one_value_args}" "")
    _kontra_require_complete_arguments("kontra_add_kernel_module" "${args_KEYWORDS_MISSING_VALUES}")
    if(NOT "${args_UNPARSED_ARGUMENTS}" STREQUAL "" OR module STREQUAL "" OR "${args_PROJECT}" STREQUAL "")
        _kontra_fail(
            invalid-arguments
            "kontra_add_kernel_module() requires a nested target and PROJECT"
        )
    endif()
    _kontra_validate_target_name("${module}" "kernel module target")
    _kontra_validate_target_name("${args_PROJECT}" "kernel project")
    _kontra_require_kernel_project("${args_PROJECT}")

    _kontra_add_kernel_module("${args_PROJECT}" "${module}" "${args_OUTPUT_NAME}")
endfunction()

# Installs one exported module as a detached Kbuild projection.
function(kontra_install_kernel_module module_target)
    _kontra_require_target("${module_target}")
    set(options)
    set(one_value_args DESTINATION COMPONENT)
    cmake_parse_arguments(PARSE_ARGV 1 args "${options}" "${one_value_args}" "")
    _kontra_require_complete_arguments("kontra_install_kernel_module" "${args_KEYWORDS_MISSING_VALUES}")
    if(NOT "${args_UNPARSED_ARGUMENTS}" STREQUAL "" OR "${args_DESTINATION}" STREQUAL "")
        _kontra_fail(
            invalid-arguments
            "kontra_install_kernel_module(${module_target}) requires DESTINATION and accepts optional COMPONENT"
        )
    endif()
    _kontra_require_kernel_module("${module_target}")

    _kontra_install_kernel_module("${module_target}" "${args_DESTINATION}" "${args_COMPONENT}")
endfunction()

# Installs every exported module in a kernel project.
function(kontra_install_kernel_project project_target)
    _kontra_require_target("${project_target}")
    set(options)
    set(one_value_args DESTINATION COMPONENT)
    cmake_parse_arguments(PARSE_ARGV 1 args "${options}" "${one_value_args}" "")
    _kontra_require_complete_arguments("kontra_install_kernel_project" "${args_KEYWORDS_MISSING_VALUES}")
    if(NOT "${args_UNPARSED_ARGUMENTS}" STREQUAL "" OR "${args_DESTINATION}" STREQUAL "")
        _kontra_fail(
            invalid-arguments
            "kontra_install_kernel_project(${project_target}) requires DESTINATION and accepts optional COMPONENT"
        )
    endif()
    _kontra_require_kernel_project("${project_target}")

    _kontra_install_kernel_project("${project_target}" "${args_DESTINATION}" "${args_COMPONENT}")
endfunction()

set_property(GLOBAL PROPERTY KONTRA_LOADED_VERSION "${KONTRA_ENTRY_VERSION}")
unset(kontra_loaded_version)
