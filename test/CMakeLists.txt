# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

set(
    KONTRABAND_TEST_KERNEL_BUILD_DIRECTORY
    ""
    CACHE PATH
    "prepared kernel build directory for the optional real-kernel test"
)

set(
    KONTRABAND_TEST_REAL_KERNEL_ARCH
    ""
    CACHE STRING
    "ARCH assignment for the optional real-kernel test"
)

option(
    KONTRABAND_TEST_REAL_KERNEL_MODPOST_WARN
    "pass KBUILD_MODPOST_WARN=1 to Kbuild in the optional real-kernel test"
    OFF
)

set(kontra_test_work_root "${CMAKE_CURRENT_BINARY_DIR}/work")
set(kontra_test_prefix "${kontra_test_work_root}/prefix")
set(kontra_test_fixture_root "${CMAKE_CURRENT_SOURCE_DIR}/fixture")
set(kontra_test_cmake_root "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
set(kontra_test_package_compatibility_version "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}")

add_test(
    NAME kontraband.diagnostics
    COMMAND "${CMAKE_COMMAND}"
        "-DKONTRA_TEST_SOURCE_ROOT=${PROJECT_SOURCE_DIR}"
        "-DKONTRA_TEST_PACKAGE_COMPATIBILITY_VERSION=${kontra_test_package_compatibility_version}"
        -P "${kontra_test_cmake_root}/test_diagnostics.cmake"
)
set_tests_properties(kontraband.diagnostics PROPERTIES TIMEOUT 30)

add_test(
    NAME kontraband.setup
    COMMAND "${CMAKE_COMMAND}"
        "-DKONTRA_TEST_SOURCE_ROOT=${PROJECT_SOURCE_DIR}"
        "-DKONTRA_TEST_WORK_ROOT=${kontra_test_work_root}"
        "-DKONTRA_TEST_PREFIX=${kontra_test_prefix}"
        -P "${kontra_test_cmake_root}/setup_packages.cmake"
)
set_tests_properties(kontraband.setup PROPERTIES
    FIXTURES_SETUP kontraband_package
    TIMEOUT 120
)

# Register one fixture script and make it depend on setting up the installed package.
function(kontra_add_script_test name script)
    add_test(
        NAME "kontraband.${name}"
        COMMAND "${CMAKE_COMMAND}"
            "-DKONTRA_TEST_SOURCE_ROOT=${PROJECT_SOURCE_DIR}"
            "-DKONTRA_TEST_FIXTURE_ROOT=${kontra_test_fixture_root}"
            "-DKONTRA_TEST_PREFIX=${kontra_test_prefix}"
            "-DKONTRA_TEST_CASE_ROOT=${kontra_test_work_root}/cases/${name}"
            "-DKONTRA_TEST_PACKAGE_COMPATIBILITY_VERSION=${kontra_test_package_compatibility_version}"
            -P "${kontra_test_cmake_root}/${script}"
    )
    set_tests_properties("kontraband.${name}" PROPERTIES
        FIXTURES_REQUIRED kontraband_package
        TIMEOUT 120
    )
endfunction()

kontra_add_script_test(attribution test_attribution.cmake)
kontra_add_script_test(assembly test_assembly.cmake)
kontra_add_script_test(arguments test_arguments.cmake)
kontra_add_script_test(bundled test_bundled.cmake)
kontra_add_script_test(core test_core.cmake)
kontra_add_script_test(global-aggregates test_global_aggregates.cmake)
kontra_add_script_test(refresh test_refresh.cmake)
kontra_add_script_test(install test_install.cmake)
kontra_add_script_test(configuration test_configuration.cmake)
kontra_add_script_test(configure-depends test_configure_depends.cmake)
kontra_add_script_test(compiler-command test_compiler_command.cmake)
kontra_add_script_test(cross-toolchain test_cross_toolchain.cmake)
kontra_add_script_test(freestanding test_freestanding.cmake)
kontra_add_script_test(concurrency test_concurrency.cmake)
kontra_add_script_test(kbuild-compatibility test_kbuild_compatibility.cmake)
kontra_add_script_test(kbuild-arguments test_kbuild_arguments.cmake)
kontra_add_script_test(kbuild-verbose test_kbuild_verbose.cmake)
kontra_add_script_test(kernel-config test_kernel_config.cmake)
kontra_add_script_test(multi-config test_multi_config.cmake)
kontra_add_script_test(unity test_unity.cmake)
kontra_add_script_test(makefiles test_makefiles.cmake)
kontra_add_script_test(make-program test_make_program.cmake)
kontra_add_script_test(failure failure/all.cmake)

if(KONTRABAND_TEST_KERNEL_BUILD_DIRECTORY)
    add_test(
        NAME kontraband.real-kernel
        COMMAND "${CMAKE_COMMAND}"
            "-DKONTRA_TEST_FIXTURE_ROOT=${kontra_test_fixture_root}"
            "-DKONTRA_TEST_PREFIX=${kontra_test_prefix}"
            "-DKONTRA_TEST_CASE_ROOT=${kontra_test_work_root}/cases/real-kernel"
            "-DKONTRA_TEST_REAL_KERNEL=${KONTRABAND_TEST_KERNEL_BUILD_DIRECTORY}"
            "-DKONTRA_TEST_REAL_KERNEL_ARCH=${KONTRABAND_TEST_REAL_KERNEL_ARCH}"
            "-DKONTRA_TEST_REAL_KERNEL_MODPOST_WARN=${KONTRABAND_TEST_REAL_KERNEL_MODPOST_WARN}"
            -P "${kontra_test_cmake_root}/test_real_kernel.cmake"
    )
    set_tests_properties(kontraband.real-kernel PROPERTIES
        FIXTURES_REQUIRED kontraband_package
        LABELS real-kernel
        TIMEOUT 180
    )
endif()
