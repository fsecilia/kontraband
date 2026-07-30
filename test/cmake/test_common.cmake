# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

# Run a command. On failure, show all of its output; on success, return the output for assertions.
function(kontra_run)
    execute_process(
        COMMAND ${ARGN}
        RESULT_VARIABLE result
        OUTPUT_VARIABLE output
        ERROR_VARIABLE error
    )
    if(NOT result EQUAL 0)
        string(JOIN " " command ${ARGN})
        message(FATAL_ERROR "command failed (${result}): ${command}\n${output}${error}")
    endif()
    set(KONTRA_LAST_OUTPUT "${output}${error}" PARENT_SCOPE)
endfunction()

function(kontra_assert_exists path)
    if(NOT EXISTS "${path}" AND NOT IS_SYMLINK "${path}")
        message(FATAL_ERROR "expected '${path}' to exist")
    endif()
endfunction()

function(kontra_assert_not_exists path)
    if(EXISTS "${path}" OR IS_SYMLINK "${path}")
        message(FATAL_ERROR "expected '${path}' not to exist")
    endif()
endfunction()

function(kontra_assert_contains path pattern)
    file(READ "${path}" text)
    if(NOT text MATCHES "${pattern}")
        message(FATAL_ERROR "'${path}' does not contain /${pattern}/\n${text}")
    endif()
endfunction()

function(kontra_assert_not_contains path pattern)
    file(READ "${path}" text)
    if(text MATCHES "${pattern}")
        message(FATAL_ERROR "'${path}' unexpectedly contains /${pattern}/\n${text}")
    endif()
endfunction()

function(kontra_assert_contains_literal path literal)
    file(READ "${path}" text)
    string(FIND "${text}" "${literal}" offset)
    if(offset EQUAL -1)
        message(FATAL_ERROR "'${path}' does not contain literal '${literal}'\n${text}")
    endif()
endfunction()

# Copy one fixture into fresh source and build directories for a test.
function(kontra_copy_fixture name out_source out_build)
    file(REMOVE_RECURSE "${KONTRA_TEST_CASE_ROOT}")
    file(MAKE_DIRECTORY "${KONTRA_TEST_CASE_ROOT}")
    file(COPY "${KONTRA_TEST_FIXTURE_ROOT}/${name}/" DESTINATION "${KONTRA_TEST_CASE_ROOT}/source")
    set("${out_source}" "${KONTRA_TEST_CASE_ROOT}/source" PARENT_SCOPE)
    set("${out_build}" "${KONTRA_TEST_CASE_ROOT}/build" PARENT_SCOPE)
endfunction()

# Configure a fixture against the installed Kontraband package and selected fake or real kernel.
function(kontra_configure source build kernel generator)
    kontra_run(
        "${CMAKE_COMMAND}" -S "${source}" -B "${build}" -G "${generator}"
        "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
        "-DFIXTURE_KERNEL_DIR=${kernel}"
        "-DCMAKE_BUILD_TYPE=Release"
        ${ARGN}
    )
    set(KONTRA_LAST_OUTPUT "${KONTRA_LAST_OUTPUT}" PARENT_SCOPE)
endfunction()
