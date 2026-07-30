# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/module.cmake")

# Quotes arbitrary text as a CMake bracket argument that cannot collide with its contents.
function(_kontra_cmake_bracket_argument value out_argument)
    set(equals)
    while(TRUE)
        string(FIND "${value}" "]${equals}]" closing_index)
        if(closing_index EQUAL -1)
            break()
        endif()
        string(APPEND equals "=")
    endwhile()
    set("${out_argument}" "[${equals}[${value}]${equals}]" PARENT_SCOPE)
endfunction()

# Adds one COPY_FILE operation to generated install(CODE).
function(_kontra_append_install_copy code_variable source destination)
    _kontra_cmake_bracket_argument("${source}" source_argument)
    _kontra_cmake_bracket_argument("${destination}" destination_argument)
    get_filename_component(parent "${destination}" DIRECTORY)
    _kontra_cmake_bracket_argument("${parent}" parent_argument)
    set(code "${${code_variable}}")
    string(APPEND code
        "file(MAKE_DIRECTORY ${parent_argument})\n"
        "file(COPY_FILE ${source_argument} ${destination_argument})\n"
    )
    set("${code_variable}" "${code}" PARENT_SCOPE)
endfunction()

# Adds the final install rule for a staged directory, optionally for one component.
function(_kontra_install_directory stage destination component)
    set(arguments DIRECTORY "${stage}/" DESTINATION "${destination}" USE_SOURCE_PERMISSIONS)
    if(NOT component STREQUAL "")
        list(APPEND arguments COMPONENT "${component}")
    endif()
    install(${arguments})
endfunction()

# Creates a private staging directory for one install rule.
function(_kontra_allocate_module_install_stage module_target project module out_stage)
    _kontra_optional_target_property("${module_target}" KONTRA_MODULE_INSTALL_RULE_COUNT install_rule)
    if(install_rule STREQUAL "")
        set(install_rule 0)
    endif()
    _kontra_module_install_stage("${project}" "${module}" "${install_rule}" stage)
    math(EXPR next_install_rule "${install_rule} + 1")
    set_property(TARGET "${module_target}" PROPERTY KONTRA_MODULE_INSTALL_RULE_COUNT "${next_install_rule}")
    set("${out_stage}" "${stage}" PARENT_SCOPE)
endfunction()

# Adds install rules for one exported module as a detached Kbuild projection.
function(_kontra_install_kernel_module module_target destination component)
    _kontra_target_property("${module_target}" KONTRA_MODULE_PROJECT project)
    _kontra_target_property("${module_target}" KONTRA_MODULE_NESTED_TARGET module)
    _kontra_target_property("${module_target}" KONTRA_MODULE_SOURCES sources)
    _kontra_target_property("${module_target}" KONTRA_MODULE_DESTINATIONS destinations)
    _kontra_require_kernel_project("${project}")
    _kontra_optional_target_property("${project}" KONTRA_KERNEL_PROJECT_KBUILD_INCLUDE kbuild_include)
    _kontra_module_build_workspace("${project}" "${module}" workspace)

    _kontra_allocate_module_install_stage("${module_target}" "${project}" "${module}" stage)
    _kontra_cmake_bracket_argument("${stage}" stage_argument)
    set(code "file(REMOVE_RECURSE ${stage_argument})\nfile(MAKE_DIRECTORY ${stage_argument})\n")

    list(LENGTH sources source_count)
    list(LENGTH destinations destination_count)
    if(NOT source_count EQUAL destination_count)
        _kontra_fail(internal-error "module '${module_target}' has an inconsistent install mapping")
    endif()
    foreach(source relative IN ZIP_LISTS sources destinations)
        _kontra_append_install_copy(code "${source}" "${stage}/${relative}")
    endforeach()
    _kontra_append_install_copy(code "${workspace}/Kbuild" "${stage}/Kbuild")
    _kontra_append_install_copy(code "${workspace}/Makefile" "${stage}/Makefile")
    if(NOT "${kbuild_include}" STREQUAL "")
        _kontra_append_install_copy(code "${kbuild_include}" "${stage}/kontra-user.kbuild")
    endif()

    set(code_arguments CODE "${code}")
    if(NOT "${component}" STREQUAL "")
        list(APPEND code_arguments COMPONENT "${component}")
    endif()
    install(${code_arguments})
    _kontra_install_directory("${stage}" "${destination}" "${component}")
endfunction()

# Adds install rules for every exported module in one kernel project.
function(_kontra_install_kernel_project project_target destination component)
    _kontra_optional_target_property("${project_target}" KONTRA_KERNEL_PROJECT_MODULE_TARGETS module_targets)
    if(NOT module_targets)
        _kontra_fail(kernel-project-has-no-modules "kernel project '${project_target}' has no exported modules")
    endif()

    set(output_names)
    foreach(module_target IN LISTS module_targets)
        _kontra_target_property("${module_target}" KONTRA_MODULE_OUTPUT_NAME output_name)
        if(output_name IN_LIST output_names)
            _kontra_fail(
                duplicate-project-install-output-name
                "kernel project '${project_target}' has multiple modules with output name '${output_name}'"
            )
        endif()
        list(APPEND output_names "${output_name}")
    endforeach()

    list(LENGTH module_targets module_count)
    foreach(module_target IN LISTS module_targets)
        _kontra_target_property("${module_target}" KONTRA_MODULE_OUTPUT_NAME output_name)
        if(module_count EQUAL 1)
            set(module_destination "${destination}")
        else()
            set(module_destination "${destination}/${output_name}")
        endif()
        _kontra_install_kernel_module("${module_target}" "${module_destination}" "${component}")
    endforeach()
endfunction()
