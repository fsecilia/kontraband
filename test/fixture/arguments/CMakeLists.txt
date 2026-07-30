# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

cmake_minimum_required(VERSION 3.31.6)
project(kontra_arguments_fixture LANGUAGES NONE)

find_package(kontraband CONFIG REQUIRED)

# Semicolons test CMake list handling. The hash cases test Make comment escaping with zero through three existing
# backslashes. Every token must reach the nested CMake/Make command unchanged.
set(fixture_optimize_argument)
if(DEFINED FIXTURE_OPTIMIZE_DEPENDENCIES)
    list(APPEND fixture_optimize_argument
        "-DCMAKE_OPTIMIZE_DEPENDENCIES:BOOL=${FIXTURE_OPTIMIZE_DEPENDENCIES}"
    )
endif()

kontra_add_kernel_project(
    kernel
    KERNEL_BUILD_DIRECTORY "${FIXTURE_KERNEL_DIR}"
    CMAKE_ARGUMENTS
        "-DFIXTURE_LIST_VALUE:STRING=alpha;beta"
        "-DFIXTURE_SECOND_VALUE:STRING=gamma"
        ${fixture_optimize_argument}
    KBUILD_ARGUMENTS
        "KONTRA_TEST_ARGUMENT=alpha;beta"
        "KONTRA_TEST_SECOND=gamma"
        [=[KONTRA_HASH_0=a#b]=]
        [=[KONTRA_HASH_1=a\#b]=]
        [=[KONTRA_HASH_2=a\\#b]=]
        [=[KONTRA_HASH_3=a\\\#b]=]
)
kontra_add_kernel_module(argument_module PROJECT kernel)
kontra_install_kernel_module(
    kernel.argument_module
    DESTINATION "src/arguments"
    COMPONENT arguments
)
