# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

cmake_minimum_required(VERSION 3.31.6)
project(kontra_cross_fixture LANGUAGES NONE)

find_package(kontraband CONFIG REQUIRED)

foreach(variable IN ITEMS FIXTURE_KERNEL_DIR FIXTURE_TARGET_PROCESSOR FIXTURE_TARGET_TRIPLE)
    if(NOT DEFINED ${variable} OR "${${variable}}" STREQUAL "")
        message(FATAL_ERROR "${variable} is required")
    endif()
endforeach()

# This fixture stops after project configuration. The test covers cross-toolchain probing and nested cache arguments;
# the ordinary and real-kernel fixtures cover module export and builds.
kontra_add_kernel_project(
    kernel_project
    KERNEL_BUILD_DIRECTORY "${FIXTURE_KERNEL_DIR}"
    KBUILD_ARGUMENTS
        "KONTRA_TEST_PROCESSOR=${FIXTURE_TARGET_PROCESSOR}"
        "KONTRA_TEST_TRIPLE=${FIXTURE_TARGET_TRIPLE}"
)
