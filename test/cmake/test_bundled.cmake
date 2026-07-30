# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

file(REMOVE_RECURSE "${KONTRA_TEST_CASE_ROOT}")
file(MAKE_DIRECTORY "${KONTRA_TEST_CASE_ROOT}")

set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel")

# add_subdirectory() provides the same public API as find_package(). If the parent enables kontraband_INSTALL,
# installing the parent also installs Kontraband itself and the detached module source tree.
set(enabled_source "${KONTRA_TEST_CASE_ROOT}/enabled")
set(enabled_build "${KONTRA_TEST_CASE_ROOT}/enabled-build")
set(enabled_prefix "${KONTRA_TEST_CASE_ROOT}/enabled-prefix")
file(MAKE_DIRECTORY "${enabled_source}/kernel")
file(COPY
    "${KONTRA_TEST_FIXTURE_ROOT}/project/kernel/entry.c"
    "${KONTRA_TEST_FIXTURE_ROOT}/project/kernel/bridge_impl.cpp"
    "${KONTRA_TEST_FIXTURE_ROOT}/project/kernel/bridge.hpp"
    DESTINATION "${enabled_source}/kernel"
)

file(WRITE "${enabled_source}/kernel/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(bundled_kernel LANGUAGES C CXX)
add_library(module OBJECT EXCLUDE_FROM_ALL)
target_sources(module PRIVATE entry.c bridge_impl.cpp bridge.hpp)
]=])

file(WRITE "${enabled_source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(bundled_parent VERSION 1.0.0 LANGUAGES NONE)
set(kontraband_INSTALL ON CACHE BOOL "install bundled Kontraband transitively" FORCE)
add_subdirectory("@KONTRA_SOURCE@" external/kontraband)
if(NOT COMMAND kontra_add_kernel_project OR NOT COMMAND kontra_add_kernel_module)
    message(FATAL_ERROR "add_subdirectory() did not expose Kontraband's public commands")
endif()
kontra_add_kernel_project(kernel_project KERNEL_BUILD_DIRECTORY "${FIXTURE_KERNEL_DIR}")
kontra_add_kernel_module(module PROJECT kernel_project OUTPUT_NAME bundled_output)
kontra_install_kernel_module(
    kernel_project.module
    DESTINATION "src/bundled-${PROJECT_VERSION}"
)
]=])
file(READ "${enabled_source}/CMakeLists.txt" enabled_cmake)
string(REPLACE "@KONTRA_SOURCE@" "${KONTRA_TEST_SOURCE_ROOT}" enabled_cmake "${enabled_cmake}")
file(WRITE "${enabled_source}/CMakeLists.txt" "${enabled_cmake}")

kontra_run(
    "${CMAKE_COMMAND}" -S "${enabled_source}" -B "${enabled_build}" -G Ninja
    "-DFIXTURE_KERNEL_DIR=${kernel}"
)
kontra_run("${CMAKE_COMMAND}" --build "${enabled_build}" --target kernel_project.module)
kontra_run("${CMAKE_COMMAND}" --install "${enabled_build}" --prefix "${enabled_prefix}")
kontra_assert_exists("${enabled_prefix}/src/bundled-1.0.0/Kbuild")
kontra_assert_not_exists("${enabled_prefix}/src/bundled-1.0.0/bundled_output.ko")
kontra_run(
    "${CMAKE_COMMAND}" -E chdir "${enabled_prefix}/src/bundled-1.0.0"
    make "KERNEL_DIR=${kernel}" modules
)
kontra_assert_exists("${enabled_prefix}/src/bundled-1.0.0/bundled_output.ko")
kontra_assert_exists("${enabled_prefix}/share/cmake/kontraband/kontraband.cmake")
kontra_assert_exists("${enabled_prefix}/share/cmake/kontraband/kontrabandConfig.cmake")

# The package installed through the parent must work on its own. This consumer knows nothing about the source-tree
# add_subdirectory() that installed it.
set(consumer_source "${KONTRA_TEST_CASE_ROOT}/consumer")
set(consumer_build "${KONTRA_TEST_CASE_ROOT}/consumer-build")
file(MAKE_DIRECTORY "${consumer_source}")
file(WRITE "${consumer_source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(installed_consumer LANGUAGES NONE)
find_package(kontraband @KONTRA_COMPAT_VERSION@ CONFIG REQUIRED)
if(NOT COMMAND kontra_add_kernel_project OR NOT COMMAND kontra_install_kernel_module)
    message(FATAL_ERROR "transitively installed package did not expose public commands")
endif()
]=])
file(READ "${consumer_source}/CMakeLists.txt" consumer_cmake)
string(REPLACE "@KONTRA_COMPAT_VERSION@" "${KONTRA_TEST_PACKAGE_COMPATIBILITY_VERSION}" consumer_cmake "${consumer_cmake}")
file(WRITE "${consumer_source}/CMakeLists.txt" "${consumer_cmake}")
kontra_run(
    "${CMAKE_COMMAND}" -S "${consumer_source}" -B "${consumer_build}" -G Ninja
    "-DCMAKE_PREFIX_PATH=${enabled_prefix}"
)

# As a subproject, Kontraband does not install itself by default. EXCLUDE_FROM_ALL still exposes its commands, but the
# parent's install should contain only the parent's rules unless it explicitly enables Kontraband installation.
set(disabled_source "${KONTRA_TEST_CASE_ROOT}/disabled")
set(disabled_build "${KONTRA_TEST_CASE_ROOT}/disabled-build")
set(disabled_prefix "${KONTRA_TEST_CASE_ROOT}/disabled-prefix")
file(MAKE_DIRECTORY "${disabled_source}")
file(WRITE "${disabled_source}/marker.txt" "bundled parent install marker\n")
file(WRITE "${disabled_source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(bundled_parent_no_install LANGUAGES NONE)
add_subdirectory("@KONTRA_SOURCE@" external/kontraband EXCLUDE_FROM_ALL)
if(NOT COMMAND kontra_add_kernel_project)
    message(FATAL_ERROR "EXCLUDE_FROM_ALL add_subdirectory() did not expose public commands")
endif()
if(kontraband_INSTALL)
    message(FATAL_ERROR "kontraband_INSTALL must default to OFF as a subproject")
endif()
install(FILES marker.txt DESTINATION share/bundled-parent)
]=])
file(READ "${disabled_source}/CMakeLists.txt" disabled_cmake)
string(REPLACE "@KONTRA_SOURCE@" "${KONTRA_TEST_SOURCE_ROOT}" disabled_cmake "${disabled_cmake}")
file(WRITE "${disabled_source}/CMakeLists.txt" "${disabled_cmake}")
kontra_run("${CMAKE_COMMAND}" -S "${disabled_source}" -B "${disabled_build}" -G Ninja)
kontra_run("${CMAKE_COMMAND}" --install "${disabled_build}" --prefix "${disabled_prefix}")
kontra_assert_exists("${disabled_prefix}/share/bundled-parent/marker.txt")
kontra_assert_not_exists("${disabled_prefix}/share/cmake/kontraband/kontraband.cmake")
