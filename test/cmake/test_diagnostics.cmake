# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

# Collect every diagnostic id emitted by the CMake code or generated Make/Kbuild files.
file(GLOB_RECURSE implementation_files LIST_DIRECTORIES FALSE
    "${KONTRA_TEST_SOURCE_ROOT}/cmake/package/*.cmake"
    "${KONTRA_TEST_SOURCE_ROOT}/cmake/package/*.in"
)
set(emitted_ids)
set(dynamic_fail_sites)
foreach(file IN LISTS implementation_files)
    file(READ "${file}" content)

    string(REGEX MATCHALL "_kontra_fail\\([ \t\r\n]*\"" dynamic_matches "${content}")
    foreach(match IN LISTS dynamic_matches)
        list(APPEND dynamic_fail_sites "${file}")
    endforeach()

    string(REGEX MATCHALL "_kontra_fail\\([ \t\r\n]*[a-z0-9-]+" fail_matches "${content}")
    foreach(match IN LISTS fail_matches)
        string(REGEX REPLACE ".*_kontra_fail\\([ \t\r\n]*([a-z0-9-]+)$" "\\1" id "${match}")
        list(APPEND emitted_ids "${id}")
    endforeach()

    string(REGEX MATCHALL "Kontraband\\[[a-z0-9-]+\\]" direct_matches "${content}")
    foreach(match IN LISTS direct_matches)
        string(REGEX REPLACE "Kontraband\\[([a-z0-9-]+)\\]" "\\1" id "${match}")
        list(APPEND emitted_ids "${id}")
    endforeach()
endforeach()
list(REMOVE_DUPLICATES emitted_ids)
list(SORT emitted_ids)

list(LENGTH dynamic_fail_sites dynamic_fail_count)
if(NOT dynamic_fail_count EQUAL 1 OR NOT dynamic_fail_sites MATCHES "toolchain\\.cmake$")
    message(FATAL_ERROR
        "diagnostic identifiers must be statically discoverable; only the Kbuild diagnostic re-raise may be dynamic: "
        "${dynamic_fail_sites}"
    )
endif()

# The diagnostics document must list every public diagnostic id.
file(STRINGS "${KONTRA_TEST_SOURCE_ROOT}/docs/diagnostics.md" diagnostic_headings REGEX "^### `[a-z0-9-]+`$")
set(documented_ids)
foreach(heading IN LISTS diagnostic_headings)
    string(REGEX REPLACE "^### `([a-z0-9-]+)`$" "\\1" id "${heading}")
    list(APPEND documented_ids "${id}")
endforeach()
list(LENGTH documented_ids documented_count)
list(REMOVE_DUPLICATES documented_ids)
list(LENGTH documented_ids unique_documented_count)
if(NOT documented_count EQUAL unique_documented_count)
    message(FATAL_ERROR "docs/diagnostics.md contains duplicate diagnostic headings")
endif()
list(SORT documented_ids)

set(undocumented_ids ${emitted_ids})
if(documented_ids)
    list(REMOVE_ITEM undocumented_ids ${documented_ids})
endif()
set(stale_ids ${documented_ids})
if(emitted_ids)
    list(REMOVE_ITEM stale_ids ${emitted_ids})
endif()
if(undocumented_ids OR stale_ids)
    message(FATAL_ERROR
        "diagnostic catalog is out of sync\n"
        "emitted but undocumented: ${undocumented_ids}\n"
        "documented but not emitted: ${stale_ids}"
    )
endif()

# Optional File API reads use CMake's ERROR_VARIABLE text to tell a missing member from malformed JSON. That wording is
# undocumented, so test it directly. A Kitware wording change should fail here instead of breaking unrelated File API
# tests.
include("${KONTRA_TEST_SOURCE_ROOT}/cmake/package/detail/file_api.cmake")
set(optional_json [[{"present": 1}]])
string(JSON ignored ERROR_VARIABLE missing_member_error GET "${optional_json}" absent)
_kontra_json_error_is_missing("${missing_member_error}" missing_member)
if(NOT missing_member)
    message(FATAL_ERROR "string(JSON) missing-member diagnostic changed: '${missing_member_error}'")
endif()

# The installed package checks its minimum CMake/File API version before expanding PACKAGE_INIT.
file(READ "${KONTRA_TEST_SOURCE_ROOT}/cmake/kontrabandConfig.cmake.in" package_config_template)
if(NOT package_config_template MATCHES "if\\(CMAKE_VERSION VERSION_LESS 3\\.31\\.6\\)")
    message(FATAL_ERROR "package config does not enforce the documented CMake minimum")
endif()

# Keep version numbers in examples equal to PROJECT_VERSION.
if(NOT DEFINED KONTRA_TEST_PACKAGE_COMPATIBILITY_VERSION OR KONTRA_TEST_PACKAGE_COMPATIBILITY_VERSION STREQUAL "")
    message(FATAL_ERROR "KONTRA_TEST_PACKAGE_COMPATIBILITY_VERSION is required")
endif()
foreach(document IN ITEMS README.md docs/guide.md)
    file(READ "${KONTRA_TEST_SOURCE_ROOT}/${document}" content)
    string(REGEX MATCHALL
        "find_package\\(kontraband[ \t]+[0-9]+\\.[0-9]+[ \t]+CONFIG[ \t]+REQUIRED\\)"
        versioned_find_package_examples
        "${content}"
    )
    if(NOT versioned_find_package_examples)
        message(FATAL_ERROR "${document} has no versioned Kontraband find_package() example")
    endif()
    foreach(example IN LISTS versioned_find_package_examples)
        if(NOT example STREQUAL
           "find_package(kontraband ${KONTRA_TEST_PACKAGE_COMPATIBILITY_VERSION} CONFIG REQUIRED)")
            message(FATAL_ERROR
                "${document} has stale Kontraband package compatibility example '${example}'; "
                "expected major.minor ${KONTRA_TEST_PACKAGE_COMPATIBILITY_VERSION}"
            )
        endif()
    endforeach()
endforeach()
