# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

cmake_minimum_required(VERSION 3.31.6)
project(kontraband VERSION 0.1.0 LANGUAGES NONE)

# Give add_subdirectory() users the same public entry point as find_package().
set(KONTRA_ENTRY_VERSION "${PROJECT_VERSION}")
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/package/kontraband.cmake")
unset(KONTRA_ENTRY_VERSION)

option(
    kontraband_INSTALL
    "Install the Kontraband CMake package"
    "${PROJECT_IS_TOP_LEVEL}"
)

if(kontraband_INSTALL)
    include(CMakePackageConfigHelpers)

    set(KONTRABAND_CMAKE_INSTALL_DIR
        "share/cmake/kontraband"
        CACHE STRING
        "install directory for the Kontraband CMake package"
    )

    configure_package_config_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/cmake/kontrabandConfig.cmake.in"
        "${CMAKE_CURRENT_BINARY_DIR}/kontrabandConfig.cmake"
        INSTALL_DESTINATION "${KONTRABAND_CMAKE_INSTALL_DIR}"
        NO_SET_AND_CHECK_MACRO
        NO_CHECK_REQUIRED_COMPONENTS_MACRO
    )

    write_basic_package_version_file(
        "${CMAKE_CURRENT_BINARY_DIR}/kontrabandConfigVersion.cmake"
        VERSION "${PROJECT_VERSION}"
        COMPATIBILITY SameMinorVersion
        ARCH_INDEPENDENT
    )

    install(
        FILES
            "${CMAKE_CURRENT_BINARY_DIR}/kontrabandConfig.cmake"
            "${CMAKE_CURRENT_BINARY_DIR}/kontrabandConfigVersion.cmake"
        DESTINATION "${KONTRABAND_CMAKE_INSTALL_DIR}"
    )

    # Install the package as one tree. kontraband.cmake is the public entry point; detail/ contains its implementation.
    install(
        DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/cmake/package/"
        DESTINATION "${KONTRABAND_CMAKE_INSTALL_DIR}"
    )

    install(
        FILES "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE"
        DESTINATION "share/licenses/kontraband"
    )
endif()

option(KONTRABAND_BUILD_TESTS "build Kontraband fixture tests" OFF)
if(KONTRABAND_BUILD_TESTS)
    enable_language(C)
    enable_language(CXX)
    include(CTest)
    if(BUILD_TESTING)
        add_subdirectory(test)
    endif()
endif()
