# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/toolchain.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/file_api.cmake")

# Allows extra nested CMake arguments only for cache entries Kontraband does not set itself.
function(_kontra_validate_nested_arguments)
    foreach(argument IN LISTS ARGN)
        if(NOT argument MATCHES "^-D([A-Za-z_][A-Za-z0-9_]*)(:[A-Za-z_][A-Za-z0-9_]*)?=(.*)$")
            _kontra_fail(
                invalid-nested-cmake-argument
                "CMAKE_ARGUMENTS entry '${argument}' must be one -D<NAME>[:<TYPE>]=<VALUE> cache argument"
            )
        endif()
        set(name "${CMAKE_MATCH_1}")
        if(name MATCHES "^CMAKE_(C|CXX|ASM)_COMPILER($|_)" OR
           name MATCHES "^CMAKE_(C|CXX|ASM)_FLAGS($|_)" OR
           name MATCHES "^CMAKE_GENERATOR($|_)" OR
           name MATCHES "^CMAKE_(BUILD_TYPE|CONFIGURATION_TYPES|TOOLCHAIN_FILE|TRY_COMPILE_TARGET_TYPE)$" OR
           name MATCHES "^CMAKE_(SYSTEM_NAME|SYSTEM_PROCESSOR|CROSSCOMPILING)$" OR
           name MATCHES "^CMAKE_(MAKE_PROGRAM|PREFIX_PATH)$" OR
           name MATCHES "^CMAKE_PROJECT_(INCLUDE(_BEFORE)?|TOP_LEVEL_INCLUDES)$" OR
           name MATCHES "^CMAKE_PROJECT_.+_INCLUDE(_BEFORE)?$" OR
           name MATCHES "^CMAKE_USER_MAKE_RULES_OVERRIDE($|_)" OR
           name STREQUAL "CMAKE_CXX_SCAN_FOR_MODULES")
            _kontra_fail(
                unsafe-nested-cmake-argument
                "CMAKE_ARGUMENTS entry '${argument}' overrides nested-project setup owned by Kontraband"
            )
        endif()
    endforeach()
endfunction()

# Copies the hook that records CMake's initial compiler flags when each nested language is enabled.
function(_kontra_prepare_compiler_baseline_hook binary_directory out_hook)
    set(metadata_directory "${binary_directory}/kontra")
    set(hook "${metadata_directory}/compiler-baseline.cmake")
    file(MAKE_DIRECTORY "${metadata_directory}")
    file(COPY_FILE
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/compiler_baseline.cmake"
        "${hook}"
    )
    set("${out_hook}" "${hook}" PARENT_SCOPE)
endfunction()

# Configures the nested project with the outer generator and Kbuild's selected compiler command.
function(_kontra_configure_nested
    source_directory
    binary_directory
    compiler
    processor
    configuration_is_multi
    configurations
    build_type
    cmake_prefix_path
    cmake_arguments
)
    # Start the nested configure with a fresh cache. Otherwise changes to Kbuild, the compiler, the generator, or the
    # project could leave old values from a previous outer configure.
    file(REMOVE_RECURSE "${binary_directory}")
    file(MAKE_DIRECTORY "${binary_directory}/.cmake/api/v1/query")
    file(WRITE "${binary_directory}/.cmake/api/v1/query/codemodel-v2" "")
    file(WRITE "${binary_directory}/.cmake/api/v1/query/cmakeFiles-v1" "")
    _kontra_prepare_compiler_baseline_hook("${binary_directory}" compiler_baseline_hook)

    if("${compiler}" STREQUAL "" OR "${processor}" STREQUAL "")
        _kontra_fail(invalid-kernel-toolchain "Kbuild reported an empty compiler command or target processor")
    endif()

    set(arguments -S "${source_directory}" -B "${binary_directory}" -G "${CMAKE_GENERATOR}")
    if(DEFINED CMAKE_MAKE_PROGRAM AND NOT CMAKE_MAKE_PROGRAM STREQUAL "")
        # CMake may not rediscover a nonstandard Ninja or Make path when reusing the same generator.
        _kontra_append_opaque_list_value(arguments "-DCMAKE_MAKE_PROGRAM:FILEPATH=${CMAKE_MAKE_PROGRAM}")
    endif()
    if(NOT "${CMAKE_GENERATOR_PLATFORM}" STREQUAL "")
        list(APPEND arguments -A "${CMAKE_GENERATOR_PLATFORM}")
    endif()
    if(NOT "${CMAKE_GENERATOR_TOOLSET}" STREQUAL "")
        list(APPEND arguments -T "${CMAKE_GENERATOR_TOOLSET}")
    endif()
    if(configuration_is_multi)
        list(JOIN configurations ";" configuration_types_value)
        _kontra_append_opaque_list_value(arguments "-DCMAKE_CONFIGURATION_TYPES=${configuration_types_value}")
    else()
        list(APPEND arguments "-DCMAKE_BUILD_TYPE=${build_type}")
    endif()
    if(NOT CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux" OR NOT "${processor}" STREQUAL "${CMAKE_HOST_SYSTEM_PROCESSOR}")
        list(APPEND arguments
            "-DCMAKE_SYSTEM_NAME=Linux"
            "-DCMAKE_SYSTEM_PROCESSOR=${processor}"
            "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY"
        )
    endif()
    list(APPEND arguments
        "-DCMAKE_CXX_SCAN_FOR_MODULES=OFF"
        "-DCMAKE_OPTIMIZE_DEPENDENCIES:BOOL=OFF"
        "-DCMAKE_TOOLCHAIN_FILE:FILEPATH="
        "-DCMAKE_USER_MAKE_RULES_OVERRIDE:FILEPATH=${compiler_baseline_hook}"
    )
    if(NOT "${cmake_prefix_path}" STREQUAL "")
        list(JOIN cmake_prefix_path ";" prefix_value)
        _kontra_append_opaque_list_value(arguments "-DCMAKE_PREFIX_PATH=${prefix_value}")
    endif()
    foreach(argument IN LISTS cmake_arguments)
        _kontra_append_opaque_list_value(arguments "${argument}")
    endforeach()

    # Kbuild owns the compiler and linker baseline. Generic CMake environment flags could affect nested configure
    # decisions even though they are not projected into Kbuild, so keep them out of the private configure.
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E env
            --unset=CFLAGS
            --unset=CXXFLAGS
            --unset=ASMFLAGS
            --unset=LDFLAGS
            "CC=${compiler}"
            "CXX=${compiler}"
            "ASM=${compiler}"
            "${CMAKE_COMMAND}" ${arguments}
        RESULT_VARIABLE result
        OUTPUT_VARIABLE output
        ERROR_VARIABLE error
    )
    if(NOT result EQUAL 0)
        _kontra_fail(kernel-project-configure-failed "nested kernel project configure failed:\n${output}${error}")
    endif()
    if(NOT "${error}" STREQUAL "")
        message(NOTICE "nested kernel project configure diagnostics:\n${error}")
    endif()
    if(NOT "${output}" STREQUAL "")
        message(VERBOSE "nested kernel project configure output:\n${output}")
    endif()
endfunction()

# Resolves and validates the nested project source directory.
function(_kontra_resolve_kernel_project_directory requested out_directory)
    if(NOT "${requested}" STREQUAL "")
        cmake_path(
            ABSOLUTE_PATH requested
            BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
            NORMALIZE
            OUTPUT_VARIABLE directory
        )
    else()
        set(directory "${CMAKE_CURRENT_SOURCE_DIR}/kernel")
        cmake_path(NORMAL_PATH directory)
    endif()
    if(NOT EXISTS "${directory}/CMakeLists.txt")
        _kontra_fail(
            missing-kernel-project
            "nested kernel project '${directory}/CMakeLists.txt' does not exist"
        )
    endif()
    set("${out_directory}" "${directory}" PARENT_SCOPE)
endfunction()

# Resolves and validates the source-tree root used for exported paths.
function(_kontra_resolve_projection_root requested out_root)
    if(NOT "${requested}" STREQUAL "")
        cmake_path(
            ABSOLUTE_PATH requested
            BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
            NORMALIZE
            OUTPUT_VARIABLE root
        )
    else()
        cmake_path(
            ABSOLUTE_PATH CMAKE_CURRENT_SOURCE_DIR
            NORMALIZE
            OUTPUT_VARIABLE root
        )
    endif()
    if(NOT IS_DIRECTORY "${root}")
        _kontra_fail(missing-projection-root "PROJECTION_ROOT '${root}' does not exist")
    endif()
    set("${out_root}" "${root}" PARENT_SCOPE)
endfunction()

# Resolves and validates the optional user Kbuild include.
function(_kontra_resolve_kbuild_include requested out_include)
    if("${requested}" STREQUAL "")
        set("${out_include}" "" PARENT_SCOPE)
        return()
    endif()

    cmake_path(
        ABSOLUTE_PATH requested
        BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        NORMALIZE
        OUTPUT_VARIABLE kbuild_include
    )
    if(NOT EXISTS "${kbuild_include}" OR IS_DIRECTORY "${kbuild_include}")
        _kontra_fail(missing-kbuild-include "KBUILD_INCLUDE '${kbuild_include}' is not a file")
    endif()
    set("${out_include}" "${kbuild_include}" PARENT_SCOPE)
endfunction()

# Reads the outer generator's configuration setup for the nested project.
function(_kontra_resolve_configuration_model out_is_multi out_configurations out_build_type)
    get_property(is_multi GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
    if(is_multi)
        set(configurations ${CMAKE_CONFIGURATION_TYPES})
        if("${configurations}" STREQUAL "")
            _kontra_fail(missing-configuration "the enclosing multi-config generator provides no configurations")
        endif()
        foreach(configuration IN LISTS configurations)
            _kontra_validate_configuration_name("${configuration}")
        endforeach()
        set(build_type "")
    elseif("${CMAKE_BUILD_TYPE}" STREQUAL "")
        _kontra_empty_configuration(configurations)
        set(build_type "")
    else()
        _kontra_validate_configuration_name("${CMAKE_BUILD_TYPE}")
        set(configurations "${CMAKE_BUILD_TYPE}")
        set(build_type "${CMAKE_BUILD_TYPE}")
    endif()

    set("${out_is_multi}" "${is_multi}" PARENT_SCOPE)
    set("${out_configurations}" "${configurations}" PARENT_SCOPE)
    set("${out_build_type}" "${build_type}" PARENT_SCOPE)
endfunction()

# Returns the private root for one outer kernel project.
function(_kontra_project_private_root project out_root)
    set(root "${CMAKE_CURRENT_BINARY_DIR}/kontra/projects/${project}")
    cmake_path(ABSOLUTE_PATH root NORMALIZE OUTPUT_VARIABLE root)
    set("${out_root}" "${root}" PARENT_SCOPE)
endfunction()

# Returns the nested CMake build directory below one private project root.
function(_kontra_project_subbuild_directory private_root out_directory)
    set("${out_directory}" "${private_root}/subbuild" PARENT_SCOPE)
endfunction()

# Returns the Kbuild compiler probe directory below one private project root.
function(_kontra_project_compiler_probe_directory private_root out_directory)
    set("${out_directory}" "${private_root}/compiler-probe" PARENT_SCOPE)
endfunction()

# Makes nested CMake inputs and the selected kernel configuration trigger outer reconfiguration when they change.
function(_kontra_register_project_configure_dependencies binary_directory kernel_directory)
    _kontra_read_cmake_files("${binary_directory}" cmake_files_json cmake_source_root)
    _kontra_cmake_inputs(cmake_files_json "${cmake_source_root}" all_cmake_inputs)
    _kontra_register_cmake_globs(cmake_files_json)
    list(APPEND all_cmake_inputs "${kernel_directory}/include/config/auto.conf")
    list(REMOVE_DUPLICATES all_cmake_inputs)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${all_cmake_inputs})
endfunction()


# Configures one kernel project and stores the information needed to export it.
function(_kontra_add_kernel_project
    project_name
    requested_directory
    requested_projection_root
    requested_kernel_directory
    requested_kbuild_include
    cmake_prefix_path
    cmake_arguments
    kbuild_arguments
)
    _kontra_resolve_kernel_project_directory("${requested_directory}" source_directory)
    _kontra_resolve_projection_root("${requested_projection_root}" projection_root)
    _kontra_resolve_kbuild_include("${requested_kbuild_include}" kbuild_include)
    _kontra_resolve_kernel_directory("${requested_kernel_directory}" kernel_directory)

    _kontra_project_private_root("${project_name}" private_root)
    _kontra_validate_kbuild_workspace_path("${private_root}" "Kontraband build directory")
    _kontra_project_subbuild_directory("${private_root}" binary_directory)
    _kontra_project_compiler_probe_directory("${private_root}" compiler_probe_directory)
    _kontra_resolve_make(make_executable)
    _kontra_probe_kernel_toolchain(
        "${kernel_directory}"
        "${compiler_probe_directory}"
        "${kbuild_arguments}"
        "${make_executable}"
        compiler
        processor
    )

    _kontra_resolve_configuration_model(
        configuration_is_multi
        configurations
        build_type
    )

    set(prefix_path ${CMAKE_PREFIX_PATH} ${cmake_prefix_path})
    list(REMOVE_DUPLICATES prefix_path)
    _kontra_configure_nested(
        "${source_directory}"
        "${binary_directory}"
        "${compiler}"
        "${processor}"
        "${configuration_is_multi}"
        "${configurations}"
        "${build_type}"
        "${prefix_path}"
        "${cmake_arguments}"
    )
    _kontra_register_project_configure_dependencies("${binary_directory}" "${kernel_directory}")

    _kontra_global_aggregate_target_names(global_aggregate_target_names)
    foreach(global_aggregate_target IN LISTS global_aggregate_target_names)
        _kontra_ensure_global_aggregate("${global_aggregate_target}")
    endforeach()
    add_custom_target("${project_name}")
    add_custom_target("${project_name}.unchecked")
    add_custom_target("${project_name}.clean")
    add_dependencies(kontra_kernel_modules.clean "${project_name}.clean")
    set_target_properties("${project_name}" PROPERTIES
        KONTRA_KERNEL_PROJECT TRUE
        KONTRA_KERNEL_PROJECT_BINARY_DIRECTORY "${binary_directory}"
        KONTRA_KERNEL_PROJECT_COMPILER_BASELINE_DIRECTORY "${binary_directory}/kontra/compiler-baseline"
        KONTRA_KERNEL_PROJECT_PROJECTION_ROOT "${projection_root}"
        KONTRA_KERNEL_PROJECT_PRIVATE_ROOT "${private_root}"
        KONTRA_KERNEL_PROJECT_KERNEL_DIRECTORY "${kernel_directory}"
        KONTRA_KERNEL_PROJECT_KBUILD_INCLUDE "${kbuild_include}"
        KONTRA_KERNEL_PROJECT_KBUILD_ARGUMENTS "${kbuild_arguments}"
        KONTRA_KERNEL_PROJECT_CONFIGURATIONS "${configurations}"
        KONTRA_KERNEL_PROJECT_MULTI_CONFIG "${configuration_is_multi}"
        KONTRA_KERNEL_PROJECT_MAKE_EXECUTABLE "${make_executable}"
        KONTRA_KERNEL_PROJECT_MODULE_TARGETS ""
    )
    set(configuration_index 0)
    foreach(encoded_configuration IN LISTS configurations)
        _kontra_load_file_api(
            "${project_name}" "${binary_directory}" "${encoded_configuration}" "${configuration_index}"
        )
        math(EXPR configuration_index "${configuration_index} + 1")
    endforeach()
    message(STATUS "Kontraband kernel project '${project_name}' configured")
endfunction()
