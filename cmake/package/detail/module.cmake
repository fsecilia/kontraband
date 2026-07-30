# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/project.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/export.cmake")

# Returns the private root for one exported nested module.
function(_kontra_module_root project module out_root)
    _kontra_target_property("${project}" KONTRA_KERNEL_PROJECT_PRIVATE_ROOT private_root)
    set("${out_root}" "${private_root}/modules/${module}" PARENT_SCOPE)
endfunction()

# Returns the private root for one module configuration.
function(_kontra_module_configuration_root project module encoded_configuration out_root)
    _kontra_module_root("${project}" "${module}" module_root)
    _kontra_decode_configuration("${encoded_configuration}" ignored_configuration configuration_directory)
    set("${out_root}" "${module_root}/${configuration_directory}" PARENT_SCOPE)
endfunction()

# Returns the development Kbuild workspace for one module configuration.
function(_kontra_module_workspace project module encoded_configuration out_workspace)
    _kontra_module_configuration_root("${project}" "${module}" "${encoded_configuration}" configuration_root)
    set("${out_workspace}" "${configuration_root}/workspace" PARENT_SCOPE)
endfunction()

# Returns the file that records which projection paths Kontraband created for one module configuration.
function(_kontra_module_files_state project module encoded_configuration out_state_file)
    _kontra_module_configuration_root("${project}" "${module}" "${encoded_configuration}" configuration_root)
    set("${out_state_file}" "${configuration_root}/state/files" PARENT_SCOPE)
endfunction()

# Returns the module configuration root in a form generator expressions can use at build time.
function(_kontra_module_build_configuration_root project module out_root)
    _kontra_target_property("${project}" KONTRA_KERNEL_PROJECT_CONFIGURATIONS configurations)
    _kontra_target_property("${project}" KONTRA_KERNEL_PROJECT_MULTI_CONFIG multi_config)
    if(multi_config)
        _kontra_module_root("${project}" "${module}" module_root)
        set(root "${module_root}/$<CONFIG>")
    else()
        _kontra_module_configuration_root("${project}" "${module}" "${configurations}" root)
    endif()
    set("${out_root}" "${root}" PARENT_SCOPE)
endfunction()

# Returns the workspace path used at build time.
function(_kontra_module_build_workspace project module out_workspace)
    _kontra_module_build_configuration_root("${project}" "${module}" configuration_root)
    set("${out_workspace}" "${configuration_root}/workspace" PARENT_SCOPE)
endfunction()

# Returns the stamp used by the unchecked build target.
function(_kontra_module_unchecked_stamp project module out_stamp)
    _kontra_module_build_configuration_root("${project}" "${module}" configuration_root)
    set("${out_stamp}" "${configuration_root}/state/unchecked.stamp" PARENT_SCOPE)
endfunction()

# Returns the staging directory for one module install rule.
function(_kontra_module_install_stage project module install_rule out_stage)
    _kontra_target_property("${project}" KONTRA_KERNEL_PROJECT_MULTI_CONFIG multi_config)
    _kontra_module_root("${project}" "${module}" module_root)
    if(multi_config)
        set(stage "${module_root}/install/$<CONFIG>/${install_rule}")
    else()
        set(stage "${module_root}/install/default/${install_rule}")
    endif()
    set("${out_stage}" "${stage}" PARENT_SCOPE)
endfunction()

# Resolves and validates the public module output name.
function(_kontra_resolve_module_output_name module requested out_name)
    if(NOT "${requested}" STREQUAL "")
        set(output_name "${requested}")
    else()
        set(output_name "${module}")
    endif()
    _kontra_validate_module_output_name("${output_name}")
    set("${out_name}" "${output_name}" PARENT_SCOPE)
endfunction()

# Chooses the outer target names for one module and makes sure they are unused.
function(_kontra_kernel_module_target_names project module out_build out_unchecked out_clean)
    set(build_target "${project}.${module}")
    set(unchecked_target "${build_target}.unchecked")
    set(clean_target "${build_target}.clean")
    if(TARGET "${build_target}" OR TARGET "${unchecked_target}" OR TARGET "${clean_target}")
        _kontra_fail(
            target-already-exists
            "generated target '${build_target}', '${unchecked_target}', or '${clean_target}' already exists"
        )
    endif()

    set("${out_build}" "${build_target}" PARENT_SCOPE)
    set("${out_unchecked}" "${unchecked_target}" PARENT_SCOPE)
    set("${out_clean}" "${clean_target}" PARENT_SCOPE)
endfunction()

# Exports one module workspace for each project configuration.
function(_kontra_export_module_configurations project module output_name out_sources out_destinations)
    _kontra_target_property("${project}" KONTRA_KERNEL_PROJECT_CONFIGURATIONS configurations)
    _kontra_target_property("${project}" KONTRA_KERNEL_PROJECT_MULTI_CONFIG multi_config)

    unset(multi_sources)
    unset(multi_destinations)
    foreach(encoded_configuration IN LISTS configurations)
        _kontra_module_workspace("${project}" "${module}" "${encoded_configuration}" workspace)
        _kontra_module_files_state("${project}" "${module}" "${encoded_configuration}" state_file)
        _kontra_export_module(
            "${project}"
            "${encoded_configuration}"
            "${module}"
            "${output_name}"
            "${workspace}"
            "${state_file}"
            module_sources
            module_destinations
            discarded_options
        )
        if(NOT "${discarded_options}" STREQUAL "")
            set(unique_discarded_options "${discarded_options}")
            list(REMOVE_DUPLICATES unique_discarded_options)
            unset(discarded_lines)
            foreach(option IN LISTS unique_discarded_options)
                set(option_occurrences 0)
                foreach(discarded_option IN LISTS discarded_options)
                    if(discarded_option STREQUAL option)
                        math(EXPR option_occurrences "${option_occurrences} + 1")
                    endif()
                endforeach()
                string(APPEND discarded_lines "\n  '${option}'")
                if(NOT option_occurrences EQUAL 1)
                    string(APPEND discarded_lines " (${option_occurrences} occurrences)")
                endif()
            endforeach()

            list(LENGTH unique_discarded_options discarded_count)
            if(discarded_count EQUAL 1)
                set(discarded_description "an unattributed nested compiler option")
            else()
                set(discarded_description "unattributed nested compiler options")
            endif()

            _kontra_decode_configuration("${encoded_configuration}" configuration ignored_configuration_directory)
            if(configuration STREQUAL "")
                set(configuration_description "default configuration")
            else()
                set(configuration_description "configuration '${configuration}'")
            endif()

            message(WARNING
                "Kontraband[unprojected-compiler-option]: kernel module '${project}.${module}' discarded "
                "${discarded_description} for ${configuration_description}:"
                "${discarded_lines}\n"
                "These options will not be used when the kernel module is compiled."
            )
        endif()

        if(multi_config)
            if(NOT DEFINED multi_sources)
                set(multi_sources "${module_sources}")
                set(multi_destinations "${module_destinations}")
            elseif(NOT "${module_sources}" STREQUAL "${multi_sources}" OR
                   NOT "${module_destinations}" STREQUAL "${multi_destinations}")
                _kontra_fail(
                    multi-config-file-sequence-mismatch
                    "module '${module}' changes its projection file sequence between configurations;"
                    " multi-config projects require one stable source-to-destination sequence"
                )
            endif()
        else()
            set(multi_sources "${module_sources}")
            set(multi_destinations "${module_destinations}")
        endif()
    endforeach()

    set("${out_sources}" "${multi_sources}" PARENT_SCOPE)
    set("${out_destinations}" "${multi_destinations}" PARENT_SCOPE)
endfunction()

# Creates the checked, unchecked, and clean outer targets for one exported module.
function(_kontra_add_module_build_targets
    project module output_name module_sources build_target unchecked_target clean_target
)
    _kontra_target_property("${project}" KONTRA_KERNEL_PROJECT_KERNEL_DIRECTORY kernel_directory)
    _kontra_optional_target_property("${project}" KONTRA_KERNEL_PROJECT_KBUILD_INCLUDE kbuild_include)
    _kontra_target_property("${project}" KONTRA_KERNEL_PROJECT_MAKE_EXECUTABLE make_executable)
    _kontra_module_build_workspace("${project}" "${module}" build_workspace)
    _kontra_module_unchecked_stamp("${project}" "${module}" unchecked_stamp)

    set(kbuild_invocation_arguments "KERNEL_DIR=${kernel_directory}")
    if(KONTRA_KBUILD_VERBOSE)
        list(APPEND kbuild_invocation_arguments "V=1")
    endif()

    set(module_output "${build_workspace}/${output_name}.ko")
    set(unchecked_dependencies ${module_sources}
        "${build_workspace}/Kbuild"
        "${build_workspace}/Makefile"
        "${kernel_directory}/include/config/auto.conf"
    )
    if(NOT "${kbuild_include}" STREQUAL "")
        list(APPEND unchecked_dependencies "${kbuild_include}")
    endif()

    # With Ninja, USES_TERMINAL puts these targets in the console pool, which has one slot. That keeps checked,
    # unchecked, and clean operations from using the same workspace at the same time. Unix Makefiles still have the
    # documented race between aggregate targets.
    add_custom_command(
        OUTPUT "${unchecked_stamp}" "${module_output}"
        COMMAND "${make_executable}" -C "${build_workspace}"
            ${kbuild_invocation_arguments} modules
        COMMAND "${CMAKE_COMMAND}" -E touch "${unchecked_stamp}"
        DEPENDS ${unchecked_dependencies}
        COMMENT "building kernel module ${output_name}.ko without a Kbuild dependency check"
        VERBATIM
        USES_TERMINAL
        JOB_SERVER_AWARE TRUE
    )
    add_custom_target("${unchecked_target}" DEPENDS "${unchecked_stamp}" "${module_output}")
    add_custom_target("${build_target}"
        COMMAND "${make_executable}" -C "${build_workspace}"
            ${kbuild_invocation_arguments} modules
        COMMENT "checking and building kernel module ${output_name}.ko"
        VERBATIM
        USES_TERMINAL
        JOB_SERVER_AWARE TRUE
    )
    add_custom_target("${clean_target}"
        COMMAND "${make_executable}" -C "${build_workspace}"
            ${kbuild_invocation_arguments} clean
        COMMAND "${CMAKE_COMMAND}" -E rm -f "${unchecked_stamp}"
        COMMENT "cleaning kernel module ${output_name}.ko"
        VERBATIM
        USES_TERMINAL
        JOB_SERVER_AWARE TRUE
    )
    add_dependencies("${project}" "${build_target}")
    add_dependencies("${project}.unchecked" "${unchecked_target}")
    add_dependencies("${project}.clean" "${clean_target}")
    add_dependencies(kontra_kernel_modules "${build_target}")
    add_dependencies(kontra_kernel_modules.unchecked "${unchecked_target}")
endfunction()

# Stores the module information used by aggregate targets and installation.
function(_kontra_publish_module project module build_target output_name module_sources module_destinations)
    set_target_properties("${build_target}" PROPERTIES
        KONTRA_KERNEL_MODULE TRUE
        KONTRA_MODULE_PROJECT "${project}"
        KONTRA_MODULE_NESTED_TARGET "${module}"
        KONTRA_MODULE_OUTPUT_NAME "${output_name}"
        KONTRA_MODULE_SOURCES "${module_sources}"
        KONTRA_MODULE_DESTINATIONS "${module_destinations}"
    )
    _kontra_optional_target_property("${project}" KONTRA_KERNEL_PROJECT_MODULE_TARGETS module_targets)
    list(APPEND module_targets "${build_target}")
    set_target_properties("${project}" PROPERTIES
        KONTRA_KERNEL_PROJECT_MODULE_TARGETS "${module_targets}"
    )
endfunction()


# Exports one nested OBJECT_LIBRARY target and creates its outer build targets.
function(_kontra_add_kernel_module project module requested_output_name)
    _kontra_resolve_module_output_name("${module}" "${requested_output_name}" output_name)
    _kontra_kernel_module_target_names(
        "${project}" "${module}"
        build_target unchecked_target clean_target
    )
    _kontra_export_module_configurations(
        "${project}" "${module}" "${output_name}" module_sources module_destinations
    )
    _kontra_add_module_build_targets(
        "${project}" "${module}" "${output_name}" "${module_sources}"
        "${build_target}" "${unchecked_target}" "${clean_target}"
    )
    _kontra_publish_module(
        "${project}" "${module}" "${build_target}" "${output_name}"
        "${module_sources}" "${module_destinations}"
    )
    message(STATUS "Kontraband kernel module '${build_target}' produces ${output_name}.ko")
endfunction()
