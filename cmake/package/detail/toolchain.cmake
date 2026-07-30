# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/arguments.cmake")

# Finds GNU Make for running Kbuild. Prefer `make`, but accept `gmake` when `make` names a different implementation.
function(_kontra_resolve_make out_executable)
    foreach(name IN ITEMS make gmake)
        unset(_kontra_make_candidate)
        find_program(_kontra_make_candidate NAMES "${name}" NO_CACHE)
        if(NOT _kontra_make_candidate)
            continue()
        endif()

        execute_process(
            COMMAND "${CMAKE_COMMAND}" -E env LC_ALL=C "${_kontra_make_candidate}" --version
            RESULT_VARIABLE result
            OUTPUT_VARIABLE output
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(result EQUAL 0 AND output MATCHES "^GNU Make([ \t]|$)")
            set("${out_executable}" "${_kontra_make_candidate}" PARENT_SCOPE)
            return()
        endif()
    endforeach()

    _kontra_fail(missing-gnu-make "could not find a GNU Make executable named 'make' or 'gmake'")
endfunction()

# Returns installed kernel build paths whose build links currently resolve to directories.
function(_kontra_installed_kernel_build_directories modules_root out_directories)
    file(GLOB candidates LIST_DIRECTORIES TRUE "${modules_root}/*/build")
    set(directories)
    foreach(candidate IN LISTS candidates)
        if(IS_DIRECTORY "${candidate}")
            list(APPEND directories "${candidate}")
        endif()
    endforeach()
    set("${out_directories}" "${directories}" PARENT_SCOPE)
endfunction()

# Finds and validates the prepared kernel build tree for one kernel project.
function(_kontra_resolve_kernel_directory requested out_directory)
    if(NOT "${requested}" STREQUAL "")
        cmake_path(ABSOLUTE_PATH requested BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" NORMALIZE OUTPUT_VARIABLE directory)
    elseif(DEFINED KONTRA_KERNEL_BUILD_DIRECTORY AND NOT KONTRA_KERNEL_BUILD_DIRECTORY STREQUAL "")
        cmake_path(ABSOLUTE_PATH KONTRA_KERNEL_BUILD_DIRECTORY NORMALIZE OUTPUT_VARIABLE directory)
    else()
        execute_process(
            COMMAND uname -r
            RESULT_VARIABLE uname_result
            OUTPUT_VARIABLE release
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(uname_result EQUAL 0 AND IS_DIRECTORY "/lib/modules/${release}/build")
            set(directory "/lib/modules/${release}/build")
        else()
            _kontra_installed_kernel_build_directories("/lib/modules" candidates)
            list(LENGTH candidates count)
            if(count EQUAL 1)
                list(GET candidates 0 directory)
                message(STATUS "Kontraband: using the only installed kernel build directory '${directory}'")
            else()
                _kontra_fail(
                    missing-kernel-build-directory
                    "KERNEL_BUILD_DIRECTORY is required when no unique prepared kernel tree can be selected"
                )
            endif()
        endif()
    endif()
    if(NOT IS_DIRECTORY "${directory}")
        _kontra_fail(missing-kernel-build-directory "kernel build directory '${directory}' does not exist")
    endif()
    _kontra_validate_kbuild_path("${directory}" "kernel build directory")
    if(NOT EXISTS "${directory}/include/config/auto.conf")
        _kontra_fail(
            unprepared-kernel-build-directory
            "kernel build directory '${directory}' has no include/config/auto.conf; prepare the kernel tree first"
        )
    endif()
    set("${out_directory}" "${directory}" PARENT_SCOPE)
endfunction()

# Renders the Kbuild toolchain probe workspace.
function(_kontra_render_kernel_toolchain_probe probe_directory kbuild_arguments)
    _kontra_quote_kbuild_arguments("${kbuild_arguments}" kontra_probe_kbuild_arguments_text)
    set(templates_root "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../templates")
    _kontra_read_template_body("${templates_root}/kbuild_toolchain.in" kontra_kbuild_toolchain)
    _kontra_read_template_body("${templates_root}/kbuild_linker.in" kontra_kbuild_linker)
    _kontra_read_template_body("${templates_root}/kbuild_compatibility.in" kontra_kbuild_compatibility)

    file(READ "${templates_root}/probe/Makefile.in" makefile_template)
    string(CONFIGURE "${makefile_template}" makefile_content @ONLY)
    file(WRITE "${probe_directory}/Makefile" "${makefile_content}")

    file(READ "${templates_root}/probe/Kbuild.in" kbuild_template)
    string(CONFIGURE "${kbuild_template}" kbuild_content @ONLY)
    file(WRITE "${probe_directory}/Kbuild" "${kbuild_content}")
endfunction()

# Runs the Kbuild toolchain probe and preserves any specific Kontraband error it reports.
function(_kontra_run_kernel_toolchain_probe kernel_directory probe_directory make_executable)
    execute_process(
        COMMAND "${make_executable}" --no-print-directory -C "${probe_directory}"
            "KERNEL_DIR=${kernel_directory}"
        RESULT_VARIABLE result
        OUTPUT_VARIABLE output
        ERROR_VARIABLE error
    )
    if(result EQUAL 0)
        return()
    endif()

    set(probe_log "${output}${error}")
    if(probe_log MATCHES "Kontraband: unsupported Kbuild; missing symbols: ([^\r\n]+)")
        _kontra_fail(
            unsupported-kbuild
            "selected kernel is missing required Kbuild symbols: ${CMAKE_MATCH_1}"
        )
    elseif(probe_log MATCHES "Kontraband\\[([a-z0-9-]+)\\]: ([^\r\n]+)")
        set(diagnostic_id "${CMAKE_MATCH_1}")
        set(diagnostic_message "${CMAKE_MATCH_2}")
        _kontra_fail("${diagnostic_id}" "${diagnostic_message}")
    endif()
    _kontra_fail(kernel-toolchain-probe-failed "Kbuild toolchain probe failed:\n${probe_log}")
endfunction()

# Reads and validates Kbuild's compiler command, linker command, and target processor.
function(_kontra_read_kernel_toolchain_probe probe_directory out_compiler out_linker out_processor)
    set(compiler_output "${probe_directory}/compiler.txt")
    set(linker_output "${probe_directory}/linker.txt")
    set(processor_output "${probe_directory}/processor.txt")
    if(NOT EXISTS "${compiler_output}" OR NOT EXISTS "${linker_output}" OR NOT EXISTS "${processor_output}")
        _kontra_fail(invalid-kernel-toolchain "Kbuild did not report CC, LD, and UTS_MACHINE")
    endif()

    file(READ "${compiler_output}" compiler)
    file(READ "${linker_output}" linker)
    file(READ "${processor_output}" processor)
    string(STRIP "${compiler}" compiler)
    string(STRIP "${linker}" linker)
    string(STRIP "${processor}" processor)
    if(compiler STREQUAL "" OR linker STREQUAL "" OR processor STREQUAL "")
        _kontra_fail(invalid-kernel-toolchain "Kbuild reported an empty CC, LD, or UTS_MACHINE")
    endif()

    set("${out_compiler}" "${compiler}" PARENT_SCOPE)
    set("${out_linker}" "${linker}" PARENT_SCOPE)
    set("${out_processor}" "${processor}" PARENT_SCOPE)
endfunction()

# Asks Kbuild which compiler, linker, and target processor it will use. The generated probe also checks the Kbuild and
# linker features Kontraband needs.
function(_kontra_probe_kernel_toolchain
    kernel_directory
    probe_directory
    kbuild_arguments
    make_executable
    out_compiler
    out_processor
)
    file(REMOVE_RECURSE "${probe_directory}")
    file(MAKE_DIRECTORY "${probe_directory}")
    _kontra_render_kernel_toolchain_probe("${probe_directory}" "${kbuild_arguments}")
    _kontra_run_kernel_toolchain_probe("${kernel_directory}" "${probe_directory}" "${make_executable}")
    _kontra_read_kernel_toolchain_probe("${probe_directory}" compiler linker processor)

    message(VERBOSE "Kontraband: Kbuild toolchain CC='${compiler}' LD='${linker}' UTS_MACHINE='${processor}'")
    set("${out_compiler}" "${compiler}" PARENT_SCOPE)
    set("${out_processor}" "${processor}" PARENT_SCOPE)
endfunction()
