# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

# This fixture runs a real Kbuild compile and link. CI may set ARCH and modpost options, but the prepared kernel decides
# which compiler and linker to use. The job using a packaged kernel keeps modpost strict.
kontra_copy_fixture(real source build)
set(real_configure_arguments)
if(DEFINED KONTRA_TEST_REAL_KERNEL_ARCH AND NOT KONTRA_TEST_REAL_KERNEL_ARCH STREQUAL "")
    list(APPEND real_configure_arguments "-DFIXTURE_ARCH=${KONTRA_TEST_REAL_KERNEL_ARCH}")
endif()
if(KONTRA_TEST_REAL_KERNEL_MODPOST_WARN)
    list(APPEND real_configure_arguments "-DFIXTURE_MODPOST_WARN=1")
endif()
kontra_configure("${source}" "${build}" "${KONTRA_TEST_REAL_KERNEL}" Ninja ${real_configure_arguments})

# Build once so CMake records the unchecked target as current, then check that the checked target can enter Kbuild even
# when CXX is unusable.
kontra_run(
    "${CMAKE_COMMAND}" -E env "CXX=/bin/false"
    "${CMAKE_COMMAND}" --build "${build}" --target kernel.kontra_real.unchecked
)
set(workspace "${build}/kontra/projects/kernel/modules/kontra_real/Release/workspace")
kontra_assert_exists("${workspace}/kontra_real.ko")

# With kernel LTO, Clang can leave intermediate objects as LLVM bitcode until the module link. Inspect ELF objects
# directly. Accept bitcode only when the recorded Kbuild command shows that LTO produced it; anything else is an error.
# CI also keeps kernel jobs without LTO so the COMDAT and vtable checks can inspect real ELF objects.
function(kontra_real_object_format path out_format)
    file(READ "${path}" magic OFFSET 0 LIMIT 4 HEX)
    string(TOLOWER "${magic}" magic)
    if(magic STREQUAL "7f454c46")
        set(format ELF)
    elseif(magic STREQUAL "4243c0de" OR magic STREQUAL "dec0170b")
        set(format LLVM_BITCODE)
    else()
        message(FATAL_ERROR "unexpected real-kernel object format for '${path}': magic ${magic}")
    endif()
    set("${out_format}" "${format}" PARENT_SCOPE)
endfunction()

function(kontra_real_assert_lto_bitcode object command_file purpose)
    kontra_assert_contains("${command_file}" "(^| )-flto(=[^ ]+)?( |$)")
    message(STATUS
        "${object} is LLVM bitcode produced by kernel LTO; ${purpose} is not an ELF intermediate-object invariant"
    )
endfunction()

# Test Kbuild's optional warning groups on one C++ object without enabling W=2/W=3 for Linux's C compilation. The
# fixture uses -Werror so a warning meant only for C fails if it leaks into C++. Run the object build through the
# generated wrapper so it uses the same toolchain, saved KBUILD_ARGUMENTS, and required arguments as the module build.
find_program(KONTRA_TEST_MAKE_EXECUTABLE NAMES make gmake REQUIRED NO_CACHE)
file(REMOVE "${workspace}/projection/kernel/support.o")
kontra_run(
    "${KONTRA_TEST_MAKE_EXECUTABLE}" -C "${workspace}"
    "KERNEL_DIR=${KONTRA_TEST_REAL_KERNEL}"
    -f "${CMAKE_CURRENT_LIST_DIR}/real_kernel_warning.mk"
    kontra-test-warning-object
)
kontra_assert_exists("${workspace}/projection/kernel/support.o")

# Two translation units emit the same function-template COMDAT. Check that the input objects really contain COMDAT
# groups, then check that the final relocatable module link allocates and removes them.
find_program(KONTRA_TEST_READELF NAMES readelf REQUIRED NO_CACHE)
foreach(comdat_source IN ITEMS comdat_a comdat_b)
    file(GLOB_RECURSE comdat_objects "${workspace}/*/${comdat_source}.o")
    list(LENGTH comdat_objects comdat_object_count)
    if(NOT comdat_object_count EQUAL 1)
        message(FATAL_ERROR "expected one ${comdat_source}.o in the real Kbuild workspace: ${comdat_objects}")
    endif()
    list(GET comdat_objects 0 comdat_object)
    get_filename_component(comdat_directory "${comdat_object}" DIRECTORY)
    set(comdat_command "${comdat_directory}/.${comdat_source}.o.cmd")
    kontra_assert_exists("${comdat_command}")

    kontra_real_object_format("${comdat_object}" comdat_format)
    if(comdat_format STREQUAL "ELF")
        kontra_run(
            "${CMAKE_COMMAND}" -E env LC_ALL=C
            "${KONTRA_TEST_READELF}" -g "${comdat_object}"
        )
        if(NOT KONTRA_LAST_OUTPUT MATCHES "COMDAT group section")
            message(FATAL_ERROR "${comdat_object} does not contain the expected template COMDAT group:
${KONTRA_LAST_OUTPUT}")
        endif()
    else()
        kontra_real_assert_lto_bitcode(
            "${comdat_object}" "${comdat_command}" "COMDAT section-group inspection"
        )
    endif()
    kontra_assert_not_contains("${comdat_command}" "(^| )-pg( |$)")
    kontra_assert_not_contains("${comdat_command}" "(^| )-mrecord-mcount( |$)")
    kontra_assert_not_contains("${comdat_command}" "(^| )-mfentry( |$)")
    kontra_assert_not_contains("${comdat_command}" "-DCC_USING_(FENTRY|NOP_MCOUNT)")
endforeach()
kontra_run(
    "${CMAKE_COMMAND}" -E env LC_ALL=C
    "${KONTRA_TEST_READELF}" -g "${workspace}/kontra_real.ko"
)
if(NOT KONTRA_LAST_OUTPUT MATCHES "There are no section groups")
    message(FATAL_ERROR
        "Kbuild's final relocatable module link retained COMDAT groups; --force-group-allocation is not effective:
"
        "${KONTRA_LAST_OUTPUT}"
    )
endif()

# Normal non-pure virtual dispatch should work without a C++ runtime from Kontraband. Requiring a vtable in the object
# makes sure the fixture exercises the ABI instead of only declaring virtual functions.
file(GLOB_RECURSE virtual_objects "${workspace}/*/virtual.o")
list(LENGTH virtual_objects virtual_object_count)
if(NOT virtual_object_count EQUAL 1)
    message(FATAL_ERROR "expected one virtual.o in the real Kbuild workspace: ${virtual_objects}")
endif()
list(GET virtual_objects 0 virtual_object)
get_filename_component(virtual_directory "${virtual_object}" DIRECTORY)
set(virtual_command "${virtual_directory}/.virtual.o.cmd")
kontra_assert_exists("${virtual_command}")
kontra_real_object_format("${virtual_object}" virtual_format)
if(virtual_format STREQUAL "ELF")
    kontra_run(
        "${CMAKE_COMMAND}" -E env LC_ALL=C
        "${KONTRA_TEST_READELF}" -Ws "${virtual_object}"
    )
    if(NOT KONTRA_LAST_OUTPUT MATCHES "_ZTV")
        message(FATAL_ERROR "real C++ virtual-dispatch fixture did not emit a vtable:
${KONTRA_LAST_OUTPUT}")
    endif()
else()
    kontra_real_assert_lto_bitcode(
        "${virtual_object}" "${virtual_command}" "pre-LTO vtable symbol inspection"
    )
endif()

kontra_run(
    "${CMAKE_COMMAND}" -E env "CXX=/bin/false"
    "${CMAKE_COMMAND}" --build "${build}" --target kernel.kontra_real
)
kontra_run(
    "${CMAKE_COMMAND}" -E env "CXX=/bin/false"
    "${CMAKE_COMMAND}" --build "${build}" --target kernel.kontra_real.unchecked
)
if(NOT KONTRA_LAST_OUTPUT MATCHES "no work to do")
    message(FATAL_ERROR "unchecked real-kernel build was not inert after checked Kbuild validation")
endif()

# The installed tree must rebuild with Kbuild alone. Make CXX unusable again to prove neither the outer build nor the
# detached build tries to find a hosted CMake C++ compiler.
set(prefix "${KONTRA_TEST_CASE_ROOT}/install")
kontra_run(
    "${CMAKE_COMMAND}" --install "${build}" --prefix "${prefix}" --component real-module
)
set(installed "${prefix}/src/kontra-real")
kontra_run(
    "${CMAKE_COMMAND}" -E env "CXX=/bin/false"
    "${CMAKE_COMMAND}" -E chdir "${installed}"
    make "KERNEL_DIR=${KONTRA_TEST_REAL_KERNEL}" modules
)
kontra_assert_exists("${installed}/kontra_real.ko")
