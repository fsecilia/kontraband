# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia
#
# Loaded by CMake while each nested language is enabled.

block()
    cmake_path(GET CMAKE_USER_MAKE_RULES_OVERRIDE PARENT_PATH _kontra_metadata_directory)
    cmake_path(GET _kontra_metadata_directory PARENT_PATH _kontra_expected_binary_directory)
    if(NOT CMAKE_BINARY_DIR STREQUAL _kontra_expected_binary_directory)
        return()
    endif()

    set(_kontra_baseline_directory "${_kontra_metadata_directory}/compiler-baseline")
    file(MAKE_DIRECTORY "${_kontra_baseline_directory}")
    get_property(_kontra_languages GLOBAL PROPERTY ENABLED_LANGUAGES)
    foreach(_kontra_language IN ITEMS C CXX ASM)
        if(NOT _kontra_language IN_LIST _kontra_languages)
            continue()
        endif()

        set(_kontra_common_name "CMAKE_${_kontra_language}_FLAGS_INIT")
        if(NOT DEFINED "${_kontra_common_name}")
            continue()
        endif()
        set(_kontra_common "${${_kontra_common_name}}")

        if(CMAKE_CONFIGURATION_TYPES)
            foreach(_kontra_configuration IN LISTS CMAKE_CONFIGURATION_TYPES)
                string(TOUPPER "${_kontra_configuration}" _kontra_configuration_upper)
                set(_kontra_configuration_name
                    "CMAKE_${_kontra_language}_FLAGS_${_kontra_configuration_upper}_INIT"
                )
                set(_kontra_baseline "${_kontra_common}")
                if(DEFINED "${_kontra_configuration_name}")
                    string(APPEND _kontra_baseline " ${${_kontra_configuration_name}}")
                endif()
                string(SHA256 _kontra_configuration_hash "${_kontra_configuration}")
                file(WRITE
                    "${_kontra_baseline_directory}/${_kontra_language}-${_kontra_configuration_hash}.txt"
                    "${_kontra_baseline}"
                )
            endforeach()
        else()
            set(_kontra_configuration "${CMAKE_BUILD_TYPE}")
            set(_kontra_baseline "${_kontra_common}")
            if(NOT _kontra_configuration STREQUAL "")
                string(TOUPPER "${_kontra_configuration}" _kontra_configuration_upper)
                set(_kontra_configuration_name
                    "CMAKE_${_kontra_language}_FLAGS_${_kontra_configuration_upper}_INIT"
                )
                if(DEFINED "${_kontra_configuration_name}")
                    string(APPEND _kontra_baseline " ${${_kontra_configuration_name}}")
                endif()
            endif()
            string(SHA256 _kontra_configuration_hash "${_kontra_configuration}")
            file(WRITE
                "${_kontra_baseline_directory}/${_kontra_language}-${_kontra_configuration_hash}.txt"
                "${_kontra_baseline}"
            )
        endif()
    endforeach()
endblock()
