# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

cmake_minimum_required(VERSION 3.31.6)
project(kontra_real_fixture LANGUAGES NONE)
find_package(kontraband CONFIG REQUIRED)
set(kernel_project_arguments KERNEL_BUILD_DIRECTORY "${FIXTURE_KERNEL_DIR}")

# The CI kernel trees prepared with modules_prepare do not have Module.symvers from a full kernel build. Those jobs set
# KBUILD_MODPOST_WARN=1 so they can still run the full Kbuild compile/link path. The job using a packaged kernel keeps
# modpost strict and checks exported symbols. The prepared kernel selects the compiler and linker.
set(kbuild_arguments)
if(DEFINED FIXTURE_ARCH AND NOT FIXTURE_ARCH STREQUAL "")
    list(APPEND kbuild_arguments "ARCH=${FIXTURE_ARCH}")
endif()
if(FIXTURE_MODPOST_WARN)
    list(APPEND kbuild_arguments "KBUILD_MODPOST_WARN=1")
endif()
if(kbuild_arguments)
    list(APPEND kernel_project_arguments KBUILD_ARGUMENTS ${kbuild_arguments})
endif()
kontra_add_kernel_project(kernel ${kernel_project_arguments})

kontra_add_kernel_module(
    kontra_real
    PROJECT kernel
)

kontra_install_kernel_module(
    kernel.kontra_real
    DESTINATION "src/kontra-real"
    COMPONENT real-module
)
