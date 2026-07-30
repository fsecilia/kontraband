# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

# Kontraband exports the CMake graph it can represent exactly. These tests cover graph shapes that must fail because
# dropping or rewriting part of them would change the resulting module.
kontra_failure_nested(unsupported_target_type_nested "C" [=[
add_library(non_object STATIC other.c)
add_library(other OBJECT other.c)
target_link_libraries(other PRIVATE non_object)
]=])
kontra_expect_configure_failure(
    unsupported-target-type
    unsupported-target-type
    "${module_outer}"
    "${unsupported_target_type_nested}"
)

kontra_failure_nested(object_collision_nested "C CXX" [=[
file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/same.c" "")
file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/same.cpp" "")
add_library(other OBJECT same.c same.cpp)
]=])
kontra_expect_configure_failure(
    object-path-collision
    object-path-collision
    "${module_outer}"
    "${object_collision_nested}"
)

kontra_failure_nested(prebuilt_object_nested "C" [=[
file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/vendor.tar.o" "not really an object")
add_library(other OBJECT other.c vendor.tar.o)
]=])
kontra_expect_configure_failure(
    prebuilt-object
    unsupported-prebuilt-object
    "${module_outer}"
    "${prebuilt_object_nested}"
)

# A source name can affect how CMake or Kbuild treats the file, so Kontraband must keep its spelling. Reject names that
# Make cannot represent safely instead of silently renaming them.
kontra_failure_nested(lowercase_asm_nested "C ASM" [=[
file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/lower.s" "")
add_library(other OBJECT other.c lower.s)
]=])
kontra_expect_configure_failure(
    lowercase-assembly
    source-language-mismatch
    "${module_outer}"
    "${lowercase_asm_nested}"
)

kontra_failure_nested(make_unsafe_path_nested "C" [=[
file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/a=b.c" "")
add_library(other OBJECT "a=b.c")
]=])
kontra_expect_configure_failure(
    make-unsafe-projection-path
    invalid-projection-path
    "${module_outer}"
    "${make_unsafe_path_nested}"
)

# Build-order and TARGET_OBJECTS edges would require Kontraband to run or reproduce another build graph before Kbuild.
# Reject them instead of treating generated files or objects like ordinary source inputs.
kontra_failure_nested(utility_dependency_nested "C" [=[
add_custom_target(generate_something COMMAND "${CMAKE_COMMAND}" -E true)
add_library(other OBJECT other.c)
add_dependencies(other generate_something)
]=])
kontra_expect_configure_failure(
    utility-dependency
    unsupported-build-order-dependency
    "${module_outer}"
    "${utility_dependency_nested}"
)

kontra_failure_nested(object_build_order_dependency_nested "C" [=[
add_library(helper OBJECT other.c)
add_library(other OBJECT other.c)
add_dependencies(other helper)
]=])
kontra_expect_configure_failure(
    object-build-order-dependency
    unsupported-build-order-dependency
    "${module_outer}"
    "${object_build_order_dependency_nested}"
)

kontra_failure_nested(target_objects_dependency_nested "C" [=[
file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/helper.c" "")
add_library(helper OBJECT helper.c)
add_library(other OBJECT other.c "$<TARGET_OBJECTS:helper>")
]=])
kontra_expect_configure_failure(
    target-objects-dependency
    unsupported-generated-source
    "${module_outer}"
    "${target_objects_dependency_nested}"
    FORBID_DIAGNOSTIC unsupported-build-order-dependency
)

kontra_failure_nested(file_generate_nested "C" [=[
file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/generated.c" CONTENT "int generated(void) { return 0; }\n")
add_library(other OBJECT other.c "${CMAKE_CURRENT_BINARY_DIR}/generated.c")
]=])
kontra_expect_configure_failure(
    file-generate-source
    unsupported-generated-source
    "${module_outer}"
    "${file_generate_nested}"
)

kontra_failure_nested(stale_custom_command_nested "C" [=[
set(generated "${CMAKE_CURRENT_BINARY_DIR}/generated.c")
file(WRITE "${generated}" "int stale(void) { return 0; }\n")
add_custom_command(
    OUTPUT "${generated}"
    COMMAND "${CMAKE_COMMAND}" -E echo "int fresh(void) { return 0; }" > "${generated}"
    VERBATIM
)
add_library(other OBJECT other.c "${generated}")
]=])
kontra_expect_configure_failure(
    stale-build-generated-source
    unsupported-generated-source
    "${module_outer}"
    "${stale_custom_command_nested}"
)

# Files generated at build time are unsupported even if an old copy already exists. An outer dependency can order the
# build, but it cannot make that old file safe to export during configure.
kontra_failure_outer(outer_generated_without_dependency [=[
set(outer_generated "${CMAKE_CURRENT_BINARY_DIR}/outer-generated.c")
add_custom_command(
    OUTPUT "${outer_generated}"
    COMMAND "${CMAKE_COMMAND}" -E touch "${outer_generated}"
)
add_custom_target(generate_outer DEPENDS "${outer_generated}")
kontra_add_kernel_project(
    kernel
    KERNEL_BUILD_DIRECTORY "@KERNEL@"
    CMAKE_ARGUMENTS "-DOUTER_GENERATED:FILEPATH=${outer_generated}"
)
kontra_add_kernel_module(other PROJECT kernel)
]=])
kontra_failure_nested(outer_generated_nested "C" [=[
set_source_files_properties("${OUTER_GENERATED}" PROPERTIES GENERATED TRUE)
add_library(other OBJECT other.c "${OUTER_GENERATED}")
]=])
kontra_expect_configure_failure(
    outer-build-generated-source
    unsupported-generated-source
    "${outer_generated_without_dependency}"
    "${outer_generated_nested}"
)

string(REPLACE
    "kontra_add_kernel_module(other PROJECT kernel)"
    "add_dependencies(kernel generate_outer)\nkontra_add_kernel_module(other PROJECT kernel)"
    outer_generated_with_dependency
    "${outer_generated_without_dependency}"
)
kontra_expect_configure_failure(
    outer-build-generated-source-explicit-dependency
    unsupported-generated-source
    "${outer_generated_with_dependency}"
    "${outer_generated_nested}"
)

# Every projected file needs a stable path under a known source, build, or projection root. Merely being reachable by
# an absolute path is not enough for a detached install.
kontra_failure_nested(homeless_source_nested "C" [=[
set(homeless "${CMAKE_CURRENT_SOURCE_DIR}/../../homeless.c")
file(WRITE "${homeless}" "int homeless(void) { return 0; }\n")
add_library(other OBJECT other.c "${homeless}")
]=])
kontra_expect_configure_failure(
    source-without-projection-home
    unprojected-path
    "${module_outer}"
    "${homeless_source_nested}"
)

# CMake marks generated sources and PCH in the codemodel. Reject those unsupported forms instead of exporting a file
# just because it happens to exist at configure time.
kontra_failure_outer(generated_source_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(generated PROJECT kernel)
]=])
kontra_failure_nested(generated_source_nested "CXX" [=[
file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/generated.cpp" "// generated\n")
set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/generated.cpp" PROPERTIES GENERATED TRUE)
add_library(generated OBJECT "${CMAKE_CURRENT_SOURCE_DIR}/generated.cpp")
]=])
kontra_expect_configure_failure(
    generated-source-in-source-tree
    unsupported-generated-source
    "${generated_source_outer}"
    "${generated_source_nested}"
)

kontra_failure_nested(precompiled_header_nested "CXX" [=[
file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/pch.hpp" "#pragma once\n#define FROM_PCH 1\n")
file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/other.cpp" "int value = FROM_PCH;\n")
add_library(other OBJECT other.cpp)
target_precompile_headers(other PRIVATE pch.hpp)
]=])
kontra_expect_configure_failure(
    precompiled-header
    unsupported-precompiled-header
    "${module_outer}"
    "${precompiled_header_nested}"
)
# A module needs at least one translation unit, and every declared source must be a file. Header-only entries are fine
# as support files, but they cannot make an otherwise empty module valid.
kontra_failure_nested(no_compilation_units_nested "C" [=[
file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/other.h" "#pragma once\n")
set_source_files_properties(other.h PROPERTIES HEADER_FILE_ONLY TRUE)
add_library(other OBJECT other.h)
set_target_properties(other PROPERTIES LINKER_LANGUAGE C)
]=])
kontra_expect_configure_failure(
    module-has-no-compilation-units
    module-has-no-compilation-units
    "${module_outer}"
    "${no_compilation_units_nested}"
)

kontra_failure_nested(source_directory_nested "C" [=[
file(MAKE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/data")
set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/data" PROPERTIES HEADER_FILE_ONLY TRUE)
add_library(other OBJECT other.c "${CMAKE_CURRENT_SOURCE_DIR}/data")
]=])
kontra_expect_configure_failure(
    source-is-directory
    source-is-directory
    "${module_outer}"
    "${source_directory_nested}"
)

# The nested File API decides which files belong to the module, but export still fails if one of those files disappears
# before the outer project creates the workspace.
kontra_failure_outer(missing_projection_file_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
file(REMOVE "${CMAKE_CURRENT_SOURCE_DIR}/kernel/vanish.h")
kontra_add_kernel_module(other PROJECT kernel)
]=])
kontra_failure_nested(missing_projection_file_nested "C" [=[
file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/vanish.h" "#pragma once\n")
set_source_files_properties(vanish.h PROPERTIES HEADER_FILE_ONLY TRUE)
add_library(other OBJECT other.c vanish.h)
]=])
kontra_expect_configure_failure(
    missing-projection-file
    missing-projection-file
    "${missing_projection_file_outer}"
    "${missing_projection_file_nested}"
)
