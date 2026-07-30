# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include_guard(GLOBAL)

# Unconditionally fails build with the given diagnostic.
# Joins message arguments without treating semicolons inside an argument as list separators.
function(_kontra_fail diagnostic_id)
    set(message)
    if(ARGC GREATER 1)
        math(EXPR last_index "${ARGC} - 1")
        foreach(index RANGE 1 ${last_index})
            set(argument "${ARGV${index}}")
            if(message STREQUAL "")
                set(message "${argument}")
            else()
                string(APPEND message " ${argument}")
            endif()
        endforeach()
    endif()
    message(FATAL_ERROR "Kontraband[${diagnostic_id}]: ${message}")
endfunction()

# Fails build if the given name is not a target.
function(_kontra_require_target target)
    if(NOT TARGET "${target}")
        _kontra_fail(missing-target "target '${target}' does not exist")
    endif()
endfunction()

# Reads an optional custom target property, returning an empty value when the property is unset.
function(_kontra_optional_target_property target property out_value)
    get_property(is_set TARGET "${target}" PROPERTY "${property}" SET)
    if(is_set)
        get_property(value TARGET "${target}" PROPERTY "${property}")
    else()
        set(value)
    endif()
    set("${out_value}" "${value}" PARENT_SCOPE)
endfunction()

# Reads a required internal target property and fails build if it is missing.
function(_kontra_target_property target property out_value)
    get_property(is_set TARGET "${target}" PROPERTY "${property}" SET)
    if(NOT is_set)
        _kontra_fail(internal-error "target '${target}' is missing required internal property '${property}'")
    endif()
    get_property(value TARGET "${target}" PROPERTY "${property}")
    set("${out_value}" "${value}" PARENT_SCOPE)
endfunction()

# Fails build unless target is a Kontraband kernel project.
function(_kontra_require_kernel_project target)
    _kontra_require_target("${target}")
    _kontra_optional_target_property("${target}" KONTRA_KERNEL_PROJECT is_kernel_project)
    if(NOT is_kernel_project)
        _kontra_fail(not-a-kernel-project "target '${target}' is not a Kontraband kernel project")
    endif()
endfunction()

# Fails build unless target is a Kontraband exported kernel module.
function(_kontra_require_kernel_module target)
    _kontra_require_target("${target}")
    _kontra_optional_target_property("${target}" KONTRA_KERNEL_MODULE is_kernel_module)
    if(NOT is_kernel_module)
        _kontra_fail(not-a-kernel-module "target '${target}' is not a Kontraband module target")
    endif()
endfunction()

# Stores an empty single-config configuration as a sentinel because CMake lists cannot keep an empty element.
function(_kontra_empty_configuration out_value)
    set("${out_value}" "<kontra-empty-configuration>" PARENT_SCOPE)
endfunction()

# Converts the empty-configuration sentinel back to the File API name and directory forms.
function(_kontra_decode_configuration encoded out_name out_directory)
    _kontra_empty_configuration(empty_configuration)
    if(encoded STREQUAL "${empty_configuration}")
        set(name "")
        set(directory default)
    else()
        set(name "${encoded}")
        set(directory "${encoded}")
    endif()
    set("${out_name}" "${name}" PARENT_SCOPE)
    set("${out_directory}" "${directory}" PARENT_SCOPE)
endfunction()

# Reports missing values from cmake_parse_arguments() with one consistent diagnostic.
function(_kontra_require_complete_arguments function_name missing_values)
    if(NOT missing_values STREQUAL "")
        list(JOIN missing_values ", " missing_text)
        _kontra_fail(
            missing-keyword-value
            "${function_name}() is missing a value for: ${missing_text}"
        )
    endif()
endfunction()

# Returns the public aggregate targets shared by every Kontraband kernel project in the enclosing build.
function(_kontra_global_aggregate_target_names out_names)
    set("${out_names}"
        kontra_kernel_modules
        kontra_kernel_modules.unchecked
        kontra_kernel_modules.clean
        PARENT_SCOPE
    )
endfunction()

# Creates a global aggregate target, but fails build if the caller already created that name.
function(_kontra_ensure_global_aggregate target)
    if(TARGET "${target}")
        _kontra_optional_target_property("${target}" KONTRA_GLOBAL_AGGREGATE owned)
        if(NOT owned)
            _kontra_fail(
                target-already-exists
                "outer target '${target}' already exists and is not owned by Kontraband"
            )
        endif()
        return()
    endif()
    add_custom_target("${target}")
    set_target_properties("${target}" PROPERTIES KONTRA_GLOBAL_AGGREGATE TRUE)
endfunction()

# Normalizes root and path lexically, then checks whether path is inside root.
# Returns the relative path when it is.
function(_kontra_path_within root path out_within out_relative)
    cmake_path(ABSOLUTE_PATH root NORMALIZE OUTPUT_VARIABLE normalized_root)
    cmake_path(ABSOLUTE_PATH path NORMALIZE OUTPUT_VARIABLE normalized_path)
    cmake_path(IS_PREFIX normalized_root "${normalized_path}" NORMALIZE within)
    cmake_path(RELATIVE_PATH normalized_path BASE_DIRECTORY "${normalized_root}" OUTPUT_VARIABLE relative)
    if(relative STREQUAL ".")
        set(relative "")
    endif()

    set("${out_within}" "${within}" PARENT_SCOPE)
    set("${out_relative}" "${relative}" PARENT_SCOPE)
endfunction()

# Checks every ASCII byte against the caller's safe regex character class.
# Non-ASCII bytes are accepted as path data instead of restricting names to English characters.
function(_kontra_ascii_bytes_are_supported value allowed_ascii_class out_supported)
    # Remove safe ASCII first so ordinary paths avoid the slower byte-by-byte loop. Keep '-' last in
    # allowed_ascii_class so the regex treats it as a literal dash.
    string(REGEX REPLACE "[${allowed_ascii_class}]" "" residue "${value}")
    if(residue STREQUAL "")
        set("${out_supported}" TRUE PARENT_SCOPE)
        return()
    endif()

    # Anything left must be non-ASCII. Unsafe ASCII characters stay in the string and fail this check; non-ASCII bytes
    # are accepted without interpreting them.
    string(HEX "${residue}" encoded)
    string(LENGTH "${encoded}" encoded_length)
    math(EXPR last_offset "${encoded_length} - 2")
    foreach(offset RANGE 0 ${last_offset} 2)
        string(SUBSTRING "${encoded}" ${offset} 2 byte_hex)
        math(EXPR byte "0x${byte_hex}")
        if(byte LESS 128)
            set("${out_supported}" FALSE PARENT_SCOPE)
            return()
        endif()
    endforeach()

    set("${out_supported}" TRUE PARENT_SCOPE)
endfunction()

# Fails build if value is not a valid ordinary CMake target name.
function(_kontra_validate_target_name value context)
    if(value STREQUAL "" OR value STREQUAL "." OR value STREQUAL ".." OR
       NOT value MATCHES "^[A-Za-z0-9_.+-]+$")
        _kontra_fail(invalid-name "${context} '${value}' is not a valid target name")
    endif()
endfunction()

# Fails build if value cannot be used safely as a configuration path component in Make.
function(_kontra_validate_configuration_name value)
    _kontra_ascii_bytes_are_supported(
        "${value}"
        "A-Za-z0-9_.+-"
        supported
    )
    if(value STREQUAL "" OR value STREQUAL "." OR value STREQUAL ".." OR NOT supported)
        _kontra_fail(
            invalid-name
            "configuration '${value}' is not representable safely as a Kbuild workspace path component"
        )
    endif()
endfunction()

# Fails build if a kernel project name collides with an aggregate, a generator target, or a build-tool special target.
function(_kontra_validate_kernel_project_name value)
    _kontra_validate_target_name("${value}" "kernel project")
    set(reserved_names
        all
        build.ninja
        clean
        CMakeCache.txt
        cmake_check_build_system
        default_target
        depend
        edit_cache
        help
        install
        package
        package_source
        preinstall
        rebuild_cache
        test
        .DEFAULT
        .DELETE_ON_ERROR
        .EXPORT_ALL_VARIABLES
        .IGNORE
        .INTERMEDIATE
        .LOW_RESOLUTION_TIME
        .NOTINTERMEDIATE
        .NOTPARALLEL
        .ONESHELL
        .PHONY
        .POSIX
        .PRECIOUS
        .SECONDARY
        .SECONDEXPANSION
        .SILENT
        .SUFFIXES
        .WAIT
    )
    _kontra_global_aggregate_target_names(global_aggregate_target_names)
    list(APPEND reserved_names ${global_aggregate_target_names})
    if(value IN_LIST reserved_names)
        _kontra_fail(invalid-name "kernel project '${value}' is a reserved target name")
    endif()
endfunction()

# Fails build if value is not a valid module output name.
function(_kontra_validate_module_output_name value)
    if(value STREQUAL "" OR NOT value MATCHES "^[A-Za-z0-9_-]+$")
        _kontra_fail(
            invalid-module-output-name
            "kernel module OUTPUT_NAME '${value}' must contain only letters, digits, underscores, and hyphens"
        )
    endif()
endfunction()

# Checks whether external-module Kbuild can represent an absolute path.
function(_kontra_kbuild_path_is_supported value allow_equals out_supported)
    if(allow_equals)
        set(allowed_ascii_class "A-Za-z0-9_.+/@=-")
    else()
        set(allowed_ascii_class "A-Za-z0-9_.+/@-")
    endif()
    _kontra_ascii_bytes_are_supported("${value}" "${allowed_ascii_class}" characters_supported)
    if(value STREQUAL "" OR NOT IS_ABSOLUTE "${value}" OR NOT characters_supported)
        set(supported FALSE)
    else()
        set(supported TRUE)
    endif()
    set("${out_supported}" "${supported}" PARENT_SCOPE)
endfunction()

# Fails build if value is not an absolute path that can be used in a quoted Kbuild assignment.
function(_kontra_validate_kbuild_path value context)
    _kontra_kbuild_path_is_supported("${value}" TRUE supported)
    if(NOT supported)
        _kontra_fail(
            unsupported-kbuild-path
            "${context} '${value}' contains characters unsupported by external-module Kbuild"
        )
    endif()
endfunction()

# Fails build if value cannot be used as external-module Kbuild's M= path.
# M= is stricter than the other Kbuild paths because Kontraband does not allow '=' in it.
function(_kontra_validate_kbuild_workspace_path value context)
    _kontra_kbuild_path_is_supported("${value}" FALSE supported)
    if(NOT supported)
        _kontra_fail(
            unsupported-kbuild-path
            "${context} '${value}' cannot be represented safely as external-module Kbuild's M= path"
        )
    endif()
endfunction()

# Fails build if a relative path cannot be written safely in generated Make/Kbuild syntax.
function(_kontra_validate_relative_path value context)
    _kontra_ascii_bytes_are_supported(
        "${value}"
        "A-Za-z0-9_.+/@-"
        characters_supported
    )
    if(value STREQUAL "" OR IS_ABSOLUTE "${value}" OR
       value MATCHES "(^|/)(\\.|\\.\\.)(/|$)" OR
       NOT characters_supported)
        _kontra_fail(invalid-projection-path "${context} '${value}' is not representable in a kernel projection")
    endif()
endfunction()

# Appends one nonempty value without treating its semicolons as CMake list separators.
# CMake lists cannot keep an empty element, so callers that need one must use a sentinel.
function(_kontra_append_opaque_list_value list_variable value)
    if(value STREQUAL "")
        _kontra_fail(internal-error "cannot append an empty opaque CMake list value")
    endif()
    string(REPLACE ";" "\\;" encoded "${value}")
    set(values "${${list_variable}}")
    list(APPEND values "${encoded}")
    set("${list_variable}" "${values}" PARENT_SCOPE)
endfunction()

# Conditionally writes a file if it changed, keeping its timestamp unchanged when regenerated contents are identical.
function(_kontra_write_if_different path content)
    if(EXISTS "${path}")
        file(READ "${path}" existing)
        if(existing STREQUAL content)
            return()
        endif()
    endif()

    get_filename_component(parent "${path}" DIRECTORY)
    file(MAKE_DIRECTORY "${parent}")
    file(WRITE "${path}" "${content}")
endfunction()

# Reads a template fragment and removes its SPDX header before embedding it.
function(_kontra_read_template_body path out_content)
    file(READ "${path}" content)
    string(REGEX REPLACE "^# SPDX-License-Identifier: MIT\r?\n\r?\n?" "" content "${content}")
    set("${out_content}" "${content}" PARENT_SCOPE)
endfunction()
