# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

# Build a graph with files from the nested source tree, a sibling INTERFACE target, external OBJECT targets, a file set,
# and a source generated during configure. Each one should get a stable projection path without exposing private paths.
file(REMOVE_RECURSE "${KONTRA_TEST_CASE_ROOT}")
set(source "${KONTRA_TEST_CASE_ROOT}/source")
set(build "${KONTRA_TEST_CASE_ROOT}/build")
file(MAKE_DIRECTORY
    "${source}/projection-root"
    "${source}/nested/app"
    "${source}/nested/shared"
    "${source}/external"
)

file(WRITE "${source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(attribution LANGUAGES NONE)
find_package(kontraband CONFIG REQUIRED)
kontra_add_kernel_project(
    kernel
    DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/nested"
    PROJECTION_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/projection-root"
    KERNEL_BUILD_DIRECTORY "@KERNEL@"
)
kontra_add_kernel_module(module PROJECT kernel)
]=])
file(READ "${source}/CMakeLists.txt" outer)
string(REPLACE "@KERNEL@" "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel" outer "${outer}")
file(WRITE "${source}/CMakeLists.txt" "${outer}")

file(WRITE "${source}/nested/generated.cpp.in" "// configured source\n")
file(WRITE "${source}/nested/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(attribution_kernel LANGUAGES CXX)
configure_file(generated.cpp.in "${CMAKE_CURRENT_BINARY_DIR}/generated.cpp" COPYONLY)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../external" external)
add_subdirectory(shared)
add_subdirectory(app)
]=])

file(WRITE "${source}/external/CMakeLists.txt" [=[
add_library(ext_a OBJECT EXCLUDE_FROM_ALL a.cpp)
add_library(ext_b OBJECT EXCLUDE_FROM_ALL b.cpp)
]=])
file(WRITE "${source}/external/a.cpp" "// SPDX-License-Identifier: MIT\n")
file(WRITE "${source}/external/b.cpp" "// SPDX-License-Identifier: MIT\n")

file(WRITE "${source}/nested/shared/CMakeLists.txt" [=[
add_library(shared_interface INTERFACE)
target_sources(shared_interface INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/shared.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared.hpp"
)
target_include_directories(shared_interface INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}")
]=])
file(WRITE "${source}/nested/shared/shared.cpp" "// SPDX-License-Identifier: MIT\n")
file(WRITE "${source}/nested/shared/shared.hpp" "// SPDX-License-Identifier: MIT\n#pragma once\n")

file(WRITE "${source}/nested/app/CMakeLists.txt" [=[
add_library(module OBJECT module.cpp "${CMAKE_BINARY_DIR}/generated.cpp")
target_sources(module PRIVATE
    FILE_SET HEADERS
    BASE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}"
    FILES module.hpp
)
target_link_libraries(module PRIVATE shared_interface ext_a ext_b)
target_include_directories(module PRIVATE "${CMAKE_BINARY_DIR}")
]=])
file(WRITE "${source}/nested/app/module.cpp" "// SPDX-License-Identifier: MIT\n")
file(WRITE "${source}/nested/app/module.hpp" "// SPDX-License-Identifier: MIT\n#pragma once\n")

# Check both Kbuild paths and the development workspace. Source files appear there as symlinks. Generated files stay
# under generated/ so installation can copy them without preserving the outer build directory layout.
kontra_configure("${source}" "${build}" "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel" Ninja)
set(workspace "${build}/kontra/projects/kernel/modules/module/Release/workspace")
set(kbuild "${workspace}/Kbuild")
kontra_assert_contains("${kbuild}" "-I\\$\\(src\\)/components/shared")
kontra_assert_contains("${kbuild}" "-I\\$\\(src\\)/generated")
kontra_assert_contains("${kbuild}" "components/shared/shared.o")
kontra_assert_contains("${kbuild}" "components/app/module.o")
kontra_assert_contains("${kbuild}" "components/ext_a/a.o")
kontra_assert_contains("${kbuild}" "components/ext_b/b.o")
kontra_assert_contains("${kbuild}" "generated/generated.o")
if(NOT IS_SYMLINK "${workspace}/components/shared/shared.hpp")
    message(FATAL_ERROR "sibling INTERFACE_SOURCE header was not projected")
endif()
if(NOT IS_SYMLINK "${workspace}/generated/generated.cpp")
    message(FATAL_ERROR "configure-time generated source was not projected")
endif()
if(NOT IS_SYMLINK "${workspace}/components/app/module.hpp")
    message(FATAL_ERROR "HEADERS file-set member was not projected")
endif()
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel.module.unchecked)

# A nested binary tree is still generated data even when it sits under the default projection root. Its location must
# not cause private outer build paths to appear in projected paths.
set(in_tree_root "${KONTRA_TEST_CASE_ROOT}/in-tree-build")
set(in_tree_source "${in_tree_root}/source")
set(in_tree_build "${in_tree_source}/build")
file(MAKE_DIRECTORY "${in_tree_source}/kernel")
file(WRITE "${in_tree_source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(attribution_in_tree LANGUAGES NONE)
find_package(kontraband CONFIG REQUIRED)
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(module PROJECT kernel)
]=])
file(READ "${in_tree_source}/CMakeLists.txt" in_tree_outer)
string(REPLACE "@KERNEL@" "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel" in_tree_outer "${in_tree_outer}")
file(WRITE "${in_tree_source}/CMakeLists.txt" "${in_tree_outer}")
file(WRITE "${in_tree_source}/kernel/base.c" "// SPDX-License-Identifier: MIT\n")
file(WRITE "${in_tree_source}/kernel/generated.c.in" "// configured source\n")
file(WRITE "${in_tree_source}/kernel/generated.h.in" "#pragma once\n")
file(WRITE "${in_tree_source}/kernel/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(attribution_in_tree_kernel LANGUAGES C)
configure_file(generated.c.in "${CMAKE_CURRENT_BINARY_DIR}/generated.c" COPYONLY)
configure_file(generated.h.in "${CMAKE_CURRENT_BINARY_DIR}/generated.h" COPYONLY)
add_library(module OBJECT base.c "${CMAKE_CURRENT_BINARY_DIR}/generated.c")
target_sources(module PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated.h")
target_include_directories(module PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
]=])
kontra_configure(
    "${in_tree_source}" "${in_tree_build}" "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel" Ninja
)
set(in_tree_workspace "${in_tree_build}/kontra/projects/kernel/modules/module/Release/workspace")
set(in_tree_kbuild "${in_tree_workspace}/Kbuild")
kontra_assert_contains("${in_tree_kbuild}" "generated/generated.o")
kontra_assert_contains("${in_tree_kbuild}" "-I\\$\\(src\\)/generated")
kontra_assert_not_contains("${in_tree_kbuild}" "projection/build/kontra")
if(NOT IS_SYMLINK "${in_tree_workspace}/generated/generated.c")
    message(FATAL_ERROR "nested build-tree source leaked into the projection namespace")
endif()

# Build an external target graph where two roots are equally good matches. Require the error for the kind of path being
# mapped instead of choosing whichever root traversal happens to visit first.
function(kontra_expect_ambiguous_attribution name kind expected_id)
    set(root "${KONTRA_TEST_CASE_ROOT}/${name}")
    set(source "${root}/source")
    set(build "${root}/build")
    set(external "${root}/external")
    file(REMOVE_RECURSE "${root}")
    file(MAKE_DIRECTORY "${source}/kernel" "${external}")

    file(WRITE "${source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(attribution_ambiguity LANGUAGES NONE)
find_package(kontraband CONFIG REQUIRED)
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(module PROJECT kernel)
]=])
    file(READ "${source}/CMakeLists.txt" outer)
    string(REPLACE "@KERNEL@" "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel" outer "${outer}")
    file(WRITE "${source}/CMakeLists.txt" "${outer}")

    file(WRITE "${external}/CMakeLists.txt" [=[
add_library(ext_a OBJECT EXCLUDE_FROM_ALL a.c)
add_library(ext_b OBJECT EXCLUDE_FROM_ALL b.c)
]=])
    file(WRITE "${external}/a.c" "// SPDX-License-Identifier: MIT\n")
    file(WRITE "${external}/b.c" "// SPDX-License-Identifier: MIT\n")
    file(WRITE "${external}/foreign.c" "// SPDX-License-Identifier: MIT\n")
    file(WRITE "${source}/kernel/module.c" "// SPDX-License-Identifier: MIT\n")

    if(kind STREQUAL "source-path")
        set(kind_setup [=[
add_library(module OBJECT module.c "@EXTERNAL@/foreign.c")
target_link_libraries(module PRIVATE ext_a ext_b)
]=])
    elseif(kind STREQUAL "include-path")
        set(kind_setup [=[
add_library(module OBJECT module.c)
target_link_libraries(module PRIVATE ext_a ext_b)
target_include_directories(module PRIVATE "@EXTERNAL@")
]=])
    else()
        message(FATAL_ERROR "unknown ambiguity fixture kind '${kind}'")
    endif()
    string(REPLACE "@EXTERNAL@" "${external}" kind_setup "${kind_setup}")

    file(WRITE "${source}/kernel/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(attribution_ambiguity_kernel LANGUAGES C)
add_subdirectory("@EXTERNAL@" external)
@KIND_SETUP@
]=])
    file(READ "${source}/kernel/CMakeLists.txt" nested)
    string(REPLACE "@EXTERNAL@" "${external}" nested "${nested}")
    string(REPLACE "@KIND_SETUP@" "${kind_setup}" nested "${nested}")
    file(WRITE "${source}/kernel/CMakeLists.txt" "${nested}")

    execute_process(
        COMMAND
            "${CMAKE_COMMAND}" -S "${source}" -B "${build}" -G Ninja
            "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
            -DCMAKE_BUILD_TYPE=Release
        RESULT_VARIABLE result
        OUTPUT_VARIABLE output
        ERROR_VARIABLE error
    )
    if(result EQUAL 0 OR NOT "${output}${error}" MATCHES "Kontraband\\[${expected_id}\\]")
        message(FATAL_ERROR
            "${kind} attribution did not fail with Kontraband[${expected_id}]:\n${output}${error}"
        )
    endif()
endfunction()

# Exercise both source and include attribution through the same ambiguous graph.
kontra_expect_ambiguous_attribution(source-ambiguity source-path ambiguous-projection)
kontra_expect_ambiguous_attribution(include-ambiguity include-path ambiguous-projection)
