# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

# Writes a nested project that may declare a CONFIGURE_DEPENDS glob.
function(kontra_write_configure_depends_nested path include_dynamic_glob)
    set(source [=[
cmake_minimum_required(VERSION 3.31.6)
project(configure_depends_kernel LANGUAGES C)
file(APPEND "${CMAKE_CURRENT_SOURCE_DIR}/configure-count.txt" "configured\n")
file(GLOB module_sources CONFIGURE_DEPENDS "src/*.c")
file(GLOB optional_sources CONFIGURE_DEPENDS "optional/*.c")
file(GLOB relative_unused CONFIGURE_DEPENDS RELATIVE "." "relative/*.c")
list(APPEND module_sources ${optional_sources})
file(GLOB_RECURSE recursive_sources
    CONFIGURE_DEPENDS
    FOLLOW_SYMLINKS
    LIST_DIRECTORIES false
    RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
    "recursive/*.c"
)
foreach(source IN LISTS recursive_sources)
    list(APPEND module_sources "${CMAKE_CURRENT_SOURCE_DIR}/${source}")
endforeach()
]=])
    if(include_dynamic_glob)
        string(APPEND source [=[
file(GLOB dynamic_sources CONFIGURE_DEPENDS "dynamic/*.c")
list(APPEND module_sources ${dynamic_sources})
]=])
    endif()
    string(APPEND source [=[
add_library(module OBJECT ${module_sources})
]=])
    file(WRITE "${path}" "${source}")
endfunction()

# Returns the number of nested configure runs recorded by the fixture.
function(kontra_configure_count path out_count)
    file(STRINGS "${path}" lines)
    list(LENGTH lines count)
    set("${out_count}" "${count}" PARENT_SCOPE)
endfunction()

function(kontra_test_configure_depends name generator)
    set(root "${KONTRA_TEST_CASE_ROOT}/${name}")
    set(source "${root}/source")
    set(build "${root}/build")
    set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel")
    file(MAKE_DIRECTORY
        "${source}/kernel/src"
        "${source}/kernel/recursive/deep"
        "${source}/kernel/recursive-linked/deep"
        "${source}/kernel/optional"
        "${source}/kernel/relative"
        "${source}/kernel/dynamic"
    )
    file(WRITE "${source}/kernel/src/a.c" "int a(void) { return 1; }\n")
    file(WRITE "${source}/kernel/recursive/deep/r.c" "int r(void) { return 2; }\n")
    file(WRITE "${source}/kernel/recursive-linked/deep/l.c" "int l(void) { return 3; }\n")
    file(WRITE "${source}/kernel/dynamic/d.c" "int d(void) { return 4; }\n")
    file(CREATE_LINK
        "${source}/kernel/recursive-linked"
        "${source}/kernel/recursive/link"
        SYMBOLIC
        RESULT link_result
    )
    if(NOT link_result STREQUAL "0")
        message(FATAL_ERROR "could not create CONFIGURE_DEPENDS test symlink: ${link_result}")
    endif()

    file(WRITE "${source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(configure_depends LANGUAGES NONE)
find_package(kontraband CONFIG REQUIRED)
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(module PROJECT kernel)
]=])
    file(READ "${source}/CMakeLists.txt" outer)
    string(REPLACE "@KERNEL@" "${kernel}" outer "${outer}")
    file(WRITE "${source}/CMakeLists.txt" "${outer}")
    set(nested "${source}/kernel/CMakeLists.txt")
    set(configure_count_file "${source}/kernel/configure-count.txt")
    kontra_write_configure_depends_nested("${nested}" FALSE)

    kontra_configure("${source}" "${build}" "${kernel}" "${generator}")
    set(workspace "${build}/kontra/projects/kernel/modules/module/Release/workspace")
    kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel.module)
    kontra_assert_exists("${workspace}/projection/kernel/src/a.c")
    kontra_assert_exists("${workspace}/projection/kernel/recursive/deep/r.c")
    kontra_assert_exists("${workspace}/projection/kernel/recursive/link/deep/l.c")
    kontra_assert_not_exists("${workspace}/projection/kernel/dynamic/d.c")

    # RELATIVE changes only how returned paths are spelled. Even an unused CONFIGURE_DEPENDS glob still checks for
    # new matches.
    kontra_configure_count("${configure_count_file}" count_before_relative_add)
    file(WRITE "${source}/kernel/relative/new.c" "int relative_new(void) { return 5; }\n")
    kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel.module)
    kontra_configure_count("${configure_count_file}" count_after_relative_add)
    if(NOT count_after_relative_add GREATER count_before_relative_add)
        message(FATAL_ERROR "relative CONFIGURE_DEPENDS glob did not trigger nested reconfiguration")
    endif()

    file(WRITE "${source}/kernel/src/b.c" "int b(void) { return 6; }\n")
    file(WRITE "${source}/kernel/recursive/deep/s.c" "int s(void) { return 7; }\n")
    file(WRITE "${source}/kernel/recursive-linked/deep/t.c" "int t(void) { return 8; }\n")
    file(WRITE "${source}/kernel/optional/o.c" "int o(void) { return 9; }\n")
    kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel.module)
    kontra_assert_exists("${workspace}/projection/kernel/src/b.c")
    kontra_assert_exists("${workspace}/projection/kernel/recursive/deep/s.c")
    kontra_assert_exists("${workspace}/projection/kernel/recursive/link/deep/t.c")
    kontra_assert_exists("${workspace}/projection/kernel/optional/o.c")
    kontra_assert_contains("${workspace}/Kbuild" "projection/kernel/src/b\\.o")
    kontra_assert_contains("${workspace}/Kbuild" "projection/kernel/recursive/deep/s\\.o")
    kontra_assert_contains("${workspace}/Kbuild" "projection/kernel/recursive/link/deep/t\\.o")
    kontra_assert_contains("${workspace}/Kbuild" "projection/kernel/optional/o\\.o")

    file(REMOVE "${source}/kernel/src/a.c" "${source}/kernel/recursive/deep/r.c")
    kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel.module)
    kontra_assert_not_exists("${workspace}/projection/kernel/src/a.c")
    kontra_assert_not_exists("${workspace}/projection/kernel/recursive/deep/r.c")
    kontra_assert_not_contains("${workspace}/Kbuild" "projection/kernel/src/a\\.o")
    kontra_assert_not_contains("${workspace}/Kbuild" "projection/kernel/recursive/deep/r\\.o")

    # Once the glob is declared, a file that already exists joins the module at the next build-system check.
    kontra_write_configure_depends_nested("${nested}" TRUE)
    kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel.module)
    kontra_assert_exists("${workspace}/projection/kernel/dynamic/d.c")
    kontra_assert_contains("${workspace}/Kbuild" "projection/kernel/dynamic/d\\.o")

    # Removing the glob removes both the source and the outer check for changed matches.
    kontra_write_configure_depends_nested("${nested}" FALSE)
    kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel.module)
    kontra_assert_not_exists("${workspace}/projection/kernel/dynamic/d.c")
    kontra_assert_not_contains("${workspace}/Kbuild" "projection/kernel/dynamic/d\\.o")
    kontra_configure_count("${configure_count_file}" count_before_unmatched_add)

    file(WRITE "${source}/kernel/dynamic/after.c" "int after(void) { return 10; }\n")
    kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel.module)
    kontra_configure_count("${configure_count_file}" count_after_unmatched_add)
    if(NOT count_after_unmatched_add EQUAL count_before_unmatched_add)
        message(FATAL_ERROR "removed CONFIGURE_DEPENDS glob still triggered nested reconfiguration")
    endif()
    kontra_assert_not_exists("${workspace}/projection/kernel/dynamic/after.c")
endfunction()

file(REMOVE_RECURSE "${KONTRA_TEST_CASE_ROOT}")
kontra_test_configure_depends(ninja Ninja)
kontra_test_configure_depends(makefiles "Unix Makefiles")
