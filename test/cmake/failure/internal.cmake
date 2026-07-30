# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

# These errors check package setup and private assumptions, not supported client configurations. Test them directly
# with the smallest setup possible so the fixtures do not look like examples of how to use Kontraband.
kontra_expect_script_failure(missing-package-version missing-package-version [=[
include("@PREFIX@/share/cmake/kontraband/kontraband.cmake")
]=])
kontra_expect_script_failure(workspace-path-collision workspace-path-collision [=[
include("@PREFIX@/share/cmake/kontraband/detail/export.cmake")
set(destination "${CMAKE_CURRENT_LIST_DIR}/occupied")
file(MAKE_DIRECTORY "${destination}")
_kontra_ensure_symlink("${CMAKE_CURRENT_LIST_DIR}/source" "${destination}")
]=])

kontra_expect_script_failure(file-api file-api [=[
include("@PREFIX@/share/cmake/kontraband/detail/file_api.cmake")
set(json "{")
_kontra_json_get(value json missing)
]=])

kontra_expect_script_failure(projection-path-collision projection-path-collision [=[
include("@PREFIX@/share/cmake/kontraband/detail/export.cmake")
set(sources first)
set(destinations same)
_kontra_claim_file(second same sources destinations)
]=])

kontra_expect_script_failure(unsupported-source-language unsupported-source-language [=[
include("@PREFIX@/share/cmake/kontraband/detail/export.cmake")
_kontra_validate_source_language(Fortran)
]=])

kontra_expect_script_failure(internal-error internal-error [=[
include("@PREFIX@/share/cmake/kontraband/detail/export.cmake")
_kontra_projected_destination("" "" "" "" "" bogus "" ignored)
]=])
kontra_expect_script_failure(opaque-empty internal-error [=[
include("@PREFIX@/share/cmake/kontraband/detail/common.cmake")
set(values existing)
_kontra_append_opaque_list_value(values "")
]=])
