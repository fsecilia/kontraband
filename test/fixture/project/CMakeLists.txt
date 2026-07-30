# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

cmake_minimum_required(VERSION 3.31.6)
project(kontra_fixture VERSION 1.2.3 LANGUAGES NONE)

find_package(kontraband CONFIG REQUIRED)

if(NOT DEFINED FIXTURE_KERNEL_DIR)
    message(FATAL_ERROR "FIXTURE_KERNEL_DIR is required")
endif()

# ARCH/LLVM/CROSS_COMPILE/LD let the tests select different real or fake Kbuild toolchains. Normal users should pass
# only the Kbuild variables their kernel build needs.
set(fixture_kbuild_arguments)
foreach(variable IN ITEMS ARCH LLVM CROSS_COMPILE LD)
    if(DEFINED FIXTURE_${variable} AND NOT FIXTURE_${variable} STREQUAL "")
        list(APPEND fixture_kbuild_arguments "${variable}=${FIXTURE_${variable}}")
    endif()
endforeach()
if(DEFINED FIXTURE_EXTRA_KBUILD_ARGUMENT AND NOT FIXTURE_EXTRA_KBUILD_ARGUMENT STREQUAL "")
    list(APPEND fixture_kbuild_arguments "${FIXTURE_EXTRA_KBUILD_ARGUMENT}")
endif()
# Exercise nested CMake arguments and a native Kbuild include in the same project.
set(fixture_kernel_project_arguments
    KERNEL_BUILD_DIRECTORY "${FIXTURE_KERNEL_DIR}"
    KBUILD_INCLUDE "${CMAKE_CURRENT_SOURCE_DIR}/kernel/options.kbuild"
    CMAKE_ARGUMENTS "-DFIXTURE_PROJECT_ARGUMENT:BOOL=ON"
)
if(fixture_kbuild_arguments)
    list(APPEND fixture_kernel_project_arguments KBUILD_ARGUMENTS ${fixture_kbuild_arguments})
endif()
kontra_add_kernel_project(kernel_project ${fixture_kernel_project_arguments})

# Register two modules so the tests cover aggregate builds and project installation as well as single-module commands.
kontra_add_kernel_module(
    fixture_module
    PROJECT kernel_project
    OUTPUT_NAME fixture_output
)
kontra_add_kernel_module(
    fixture_aux
    PROJECT kernel_project
)

# Module installation covers the common DKMS case. Project installation also checks the multi-module directory layout.
kontra_install_kernel_module(
    kernel_project.fixture_module
    DESTINATION "src/fixture-${PROJECT_VERSION}"
    COMPONENT dkms-module
)
kontra_install_kernel_project(
    kernel_project
    DESTINATION "share/fixture/modules"
    COMPONENT dkms-all
)
