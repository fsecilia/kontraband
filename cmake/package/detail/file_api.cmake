# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

# Reads a required JSON value from the caller's document variable and fails if the data is missing or malformed.
function(_kontra_json_get out_value json_variable)
    string(JSON value ERROR_VARIABLE error GET "${${json_variable}}" ${ARGN})
    if(error)
        _kontra_fail(file-api "could not read File API path '${ARGN}': ${error}")
    endif()
    set("${out_value}" "${value}" PARENT_SCOPE)
endfunction()

# Reads the length of a required JSON array or object from the caller's document variable.
function(_kontra_json_length out_value json_variable)
    string(JSON value ERROR_VARIABLE error LENGTH "${${json_variable}}" ${ARGN})
    if(error)
        _kontra_fail(file-api "could not read File API length '${ARGN}': ${error}")
    endif()
    set("${out_value}" "${value}" PARENT_SCOPE)
endfunction()

# Tells a missing optional JSON member apart from malformed File API data.
function(_kontra_json_error_is_missing error out_missing)
    if(error MATCHES "^member '.+' not found$")
        set(missing TRUE)
    else()
        set(missing FALSE)
    endif()
    set("${out_missing}" "${missing}" PARENT_SCOPE)
endfunction()

# Reads an optional File API JSON value and fails if the JSON is malformed.
function(_kontra_json_optional_get out_value json_variable)
    string(JSON value ERROR_VARIABLE error GET "${${json_variable}}" ${ARGN})
    if(error)
        _kontra_json_error_is_missing("${error}" missing)
        if(NOT missing)
            _kontra_fail(file-api "could not read optional File API path '${ARGN}': ${error}")
        endif()
        set(value)
    endif()
    set("${out_value}" "${value}" PARENT_SCOPE)
endfunction()

# Reads the length of an optional JSON array and fails if the JSON is malformed.
function(_kontra_json_optional_length out_value json_variable)
    string(JSON value ERROR_VARIABLE error LENGTH "${${json_variable}}" ${ARGN})
    if(error)
        _kontra_json_error_is_missing("${error}" missing)
        if(NOT missing)
            _kontra_fail(file-api "could not read optional File API length '${ARGN}': ${error}")
        endif()
        set(value 0)
    endif()
    set("${out_value}" "${value}" PARENT_SCOPE)
endfunction()

# Returns valid zero-based indices for an array length.
function(_kontra_indices_for_length length out_indices)
    set(indices)
    if(length GREATER 0)
        math(EXPR last "${length} - 1")
        foreach(index RANGE 0 "${last}")
            list(APPEND indices "${index}")
        endforeach()
    endif()
    set("${out_indices}" "${indices}" PARENT_SCOPE)
endfunction()

# Returns valid indices for a required JSON array.
function(_kontra_json_indices out_indices json_variable)
    _kontra_json_length(length "${json_variable}" ${ARGN})
    _kontra_indices_for_length("${length}" indices)
    set("${out_indices}" "${indices}" PARENT_SCOPE)
endfunction()

# Returns valid indices for an optional JSON array.
function(_kontra_json_optional_indices out_indices json_variable)
    _kontra_json_optional_length(length "${json_variable}" ${ARGN})
    _kontra_indices_for_length("${length}" indices)
    set("${out_indices}" "${indices}" PARENT_SCOPE)
endfunction()

# Loads the newest CMake File API index and returns its reply directory.
function(_kontra_read_file_api_index build_directory out_reply_directory out_index_json)
    set(reply_directory "${build_directory}/.cmake/api/v1/reply")
    file(GLOB indexes "${reply_directory}/index-*.json")
    list(SORT indexes)
    if(NOT indexes)
        _kontra_fail(file-api "nested project produced no File API reply under '${reply_directory}'")
    endif()
    list(GET indexes -1 index_path)
    file(READ "${index_path}" index_json)
    set("${out_reply_directory}" "${reply_directory}" PARENT_SCOPE)
    set("${out_index_json}" "${index_json}" PARENT_SCOPE)
endfunction()

# Returns the project property used to store one encoded configuration.
function(_kontra_file_api_configuration_index project encoded_configuration out_index)
    _kontra_target_property("${project}" KONTRA_KERNEL_PROJECT_CONFIGURATIONS configurations)
    list(FIND configurations "${encoded_configuration}" index)
    if(index EQUAL -1)
        _kontra_fail(
            internal-error
            "kernel project '${project}' has no encoded configuration '${encoded_configuration}'"
        )
    endif()
    set("${out_index}" "${index}" PARENT_SCOPE)
endfunction()

# Reads one value from a File API snapshot stored on the project target.
function(_kontra_file_api_property project encoded_configuration property out_value)
    _kontra_file_api_configuration_index("${project}" "${encoded_configuration}" index)
    _kontra_target_property("${project}" "KONTRA_FILE_API_${index}_${property}" value)
    set("${out_value}" "${value}" PARENT_SCOPE)
endfunction()

# Loads one nested codemodel configuration into lookup properties on the project target.
function(_kontra_load_file_api project build_directory encoded_configuration configuration_index)
    _kontra_decode_configuration("${encoded_configuration}" configuration ignored_configuration_directory)
    _kontra_read_file_api_index("${build_directory}" reply_directory index_json)
    _kontra_json_get(codemodel_file index_json reply codemodel-v2 jsonFile)
    file(READ "${reply_directory}/${codemodel_file}" codemodel_json)
    _kontra_json_get(source_root codemodel_json paths source)
    cmake_path(ABSOLUTE_PATH source_root NORMALIZE OUTPUT_VARIABLE source_root)
    _kontra_json_get(build_root codemodel_json paths build)
    cmake_path(ABSOLUTE_PATH build_root NORMALIZE OUTPUT_VARIABLE build_root)

    _kontra_json_indices(configuration_indices codemodel_json configurations)
    list(LENGTH configuration_indices configuration_count)
    unset(selected)
    foreach(index IN LISTS configuration_indices)
        _kontra_json_get(candidate codemodel_json configurations "${index}")
        _kontra_json_optional_get(name candidate name)
        if(name STREQUAL "${configuration}" OR
           (configuration_count EQUAL 1 AND name STREQUAL ""))
            set(selected "${candidate}")
            break()
        endif()
    endforeach()
    if(NOT DEFINED selected)
        _kontra_fail(missing-configuration "nested codemodel has no configuration '${configuration}'")
    endif()

    set(names)
    set(ids)
    set(files)
    set(source_bases)
    set(build_bases)
    _kontra_json_indices(target_indices selected targets)
    foreach(index IN LISTS target_indices)
        _kontra_json_get(reference selected targets "${index}")
        _kontra_json_get(name reference name)
        _kontra_json_get(id reference id)
        _kontra_json_get(json_file reference jsonFile)
        set(target_file "${reply_directory}/${json_file}")
        file(READ "${target_file}" target_json)
        _kontra_json_get(target_source target_json paths source)
        _kontra_json_get(target_build target_json paths build)
        cmake_path(ABSOLUTE_PATH target_source BASE_DIRECTORY "${source_root}" NORMALIZE OUTPUT_VARIABLE target_source)
        cmake_path(ABSOLUTE_PATH target_build BASE_DIRECTORY "${build_root}" NORMALIZE OUTPUT_VARIABLE target_build)
        list(APPEND names "${name}")
        list(APPEND ids "${id}")
        list(APPEND files "${target_file}")
        list(APPEND source_bases "${target_source}")
        list(APPEND build_bases "${target_build}")
    endforeach()

    set(prefix "KONTRA_FILE_API_${configuration_index}")
    set_property(TARGET "${project}" PROPERTY "${prefix}_SOURCE_ROOT" "${source_root}")
    set_property(TARGET "${project}" PROPERTY "${prefix}_BUILD_ROOT" "${build_root}")
    set_property(TARGET "${project}" PROPERTY "${prefix}_TARGET_NAMES" "${names}")
    set_property(TARGET "${project}" PROPERTY "${prefix}_TARGET_IDS" "${ids}")
    set_property(TARGET "${project}" PROPERTY "${prefix}_TARGET_FILES" "${files}")
    set_property(TARGET "${project}" PROPERTY "${prefix}_TARGET_SOURCE_BASES" "${source_bases}")
    set_property(TARGET "${project}" PROPERTY "${prefix}_TARGET_BUILD_BASES" "${build_bases}")
endfunction()

# Reads the nested cmakeFiles reply and resolves its source root.
function(_kontra_read_cmake_files build_directory out_json out_source_root)
    _kontra_read_file_api_index("${build_directory}" reply_directory index_json)
    _kontra_json_get(cmake_files_file index_json reply cmakeFiles-v1 jsonFile)
    file(READ "${reply_directory}/${cmake_files_file}" cmake_files_json)
    _kontra_json_get(cmake_source_root cmake_files_json paths source)
    cmake_path(ABSOLUTE_PATH cmake_source_root NORMALIZE OUTPUT_VARIABLE cmake_source_root)
    set("${out_json}" "${cmake_files_json}" PARENT_SCOPE)
    set("${out_source_root}" "${cmake_source_root}" PARENT_SCOPE)
endfunction()

# Collects nested CMake input files so the outer project reconfigures when they change.
function(_kontra_cmake_inputs cmake_files_json_variable cmake_source_root out_cmake_inputs)
    set(cmake_inputs)
    _kontra_json_indices(input_indices "${cmake_files_json_variable}" inputs)
    foreach(index IN LISTS input_indices)
        _kontra_json_get(record "${cmake_files_json_variable}" inputs "${index}")
        _kontra_json_get(path record path)
        _kontra_json_optional_get(generated record isGenerated)
        _kontra_json_optional_get(cmake_builtin record isCMake)
        if(generated OR cmake_builtin)
            continue()
        endif()
        cmake_path(ABSOLUTE_PATH path BASE_DIRECTORY "${cmake_source_root}" NORMALIZE OUTPUT_VARIABLE path)
        list(APPEND cmake_inputs "${path}")
    endforeach()
    list(REMOVE_DUPLICATES cmake_inputs)
    set("${out_cmake_inputs}" "${cmake_inputs}" PARENT_SCOPE)
endfunction()

# Recreates nested CONFIGURE_DEPENDS globs in the outer build so changes to their matches trigger reconfiguration.
function(_kontra_register_cmake_globs cmake_files_json_variable)
    _kontra_json_optional_indices(glob_indices "${cmake_files_json_variable}" globsDependent)
    foreach(index IN LISTS glob_indices)
        _kontra_json_get(record "${cmake_files_json_variable}" globsDependent "${index}")
        _kontra_json_get(expression record expression)
        if(NOT IS_ABSOLUTE "${expression}")
            _kontra_fail(file-api "CONFIGURE_DEPENDS glob expression '${expression}' is not absolute")
        endif()
        _kontra_json_optional_get(recurse record recurse)
        _kontra_json_optional_get(list_directories record listDirectories)
        _kontra_json_optional_get(follow_symlinks record followSymlinks)

        # Only the set of matches matters here. RELATIVE changes how paths are spelled, not which files match.
        set(arguments CONFIGURE_DEPENDS)
        if(list_directories)
            list(APPEND arguments LIST_DIRECTORIES true)
        else()
            list(APPEND arguments LIST_DIRECTORIES false)
        endif()
        if(follow_symlinks)
            if(NOT recurse)
                _kontra_fail(file-api "non-recursive File API glob unexpectedly follows symlinks")
            endif()
            list(APPEND arguments FOLLOW_SYMLINKS)
        endif()
        # The result is unused. Calling file(GLOB ... CONFIGURE_DEPENDS) registers CMake's check for changed matches.
        if(recurse)
            file(GLOB_RECURSE ignored_matches ${arguments} "${expression}")
        else()
            file(GLOB ignored_matches ${arguments} "${expression}")
        endif()
    endforeach()
endfunction()

# Finds one target row in the configuration snapshot stored on the project target.
function(_kontra_file_api_target_index project encoded_configuration target out_index)
    _kontra_file_api_property("${project}" "${encoded_configuration}" TARGET_NAMES names)
    list(FIND names "${target}" index)
    if(index EQUAL -1)
        _kontra_fail(missing-module-target "nested project has no target '${target}' in the selected configuration")
    endif()
    set("${out_index}" "${index}" PARENT_SCOPE)
endfunction()

# Finds the File API reply file for a given target name.
function(_kontra_target_file_by_name project encoded_configuration target out_file)
    _kontra_file_api_target_index("${project}" "${encoded_configuration}" "${target}" index)
    _kontra_file_api_property("${project}" "${encoded_configuration}" TARGET_FILES files)
    list(GET files "${index}" file)
    set("${out_file}" "${file}" PARENT_SCOPE)
endfunction()

# Finds a required name by id and fails if the codemodel refers to an unknown id.
function(_kontra_target_name_by_id project encoded_configuration id out_name)
    _kontra_file_api_property("${project}" "${encoded_configuration}" TARGET_IDS ids)
    _kontra_file_api_property("${project}" "${encoded_configuration}" TARGET_NAMES names)
    list(FIND ids "${id}" index)
    if(index EQUAL -1)
        _kontra_fail(file-api "target dependency id '${id}' is absent from the selected codemodel")
    endif()
    list(GET names "${index}" name)
    set("${out_name}" "${name}" PARENT_SCOPE)
endfunction()

# Reads file for a given target.
function(_kontra_read_target project encoded_configuration target out_json)
    _kontra_target_file_by_name("${project}" "${encoded_configuration}" "${target}" file)
    file(READ "${file}" json)
    set("${out_json}" "${json}" PARENT_SCOPE)
endfunction()

# Resolves one File API backtrace node here so callers do not need to work with graph indexes.
function(_kontra_backtrace_frame target_json_variable backtrace out_file out_line out_command out_parent)
    _kontra_json_get(node "${target_json_variable}" backtraceGraph nodes "${backtrace}")

    _kontra_json_optional_get(file_index node file)
    if("${file_index}" STREQUAL "")
        set(file)
    else()
        _kontra_json_get(file "${target_json_variable}" backtraceGraph files "${file_index}")
    endif()

    _kontra_json_optional_get(line node line)
    _kontra_json_optional_get(command_index node command)
    if("${command_index}" STREQUAL "")
        set(command)
    else()
        _kontra_json_get(command "${target_json_variable}" backtraceGraph commands "${command_index}")
    endif()
    _kontra_json_optional_get(parent node parent)

    set("${out_file}" "${file}" PARENT_SCOPE)
    set("${out_line}" "${line}" PARENT_SCOPE)
    set("${out_command}" "${command}" PARENT_SCOPE)
    set("${out_parent}" "${parent}" PARENT_SCOPE)
endfunction()

# Returns the CMake command for a File API record, or empty if no declaration command is available.
function(_kontra_record_backtrace_command target_json_variable record_json_variable out_command)
    _kontra_json_optional_get(backtrace "${record_json_variable}" backtrace)
    if("${backtrace}" STREQUAL "")
        set("${out_command}" "" PARENT_SCOPE)
        return()
    endif()

    _kontra_backtrace_frame(
        "${target_json_variable}" "${backtrace}"
        ignored_file ignored_line command ignored_parent
    )
    set("${out_command}" "${command}" PARENT_SCOPE)
endfunction()

# Walks reachable object targets in deterministic postorder and rejects graph edges Kontraband cannot represent.
function(_kontra_visit_object_target project encoded_configuration target visited order out_visited out_order)
    if(target IN_LIST visited)
        set("${out_visited}" "${visited}" PARENT_SCOPE)
        set("${out_order}" "${order}" PARENT_SCOPE)
        return()
    endif()

    _kontra_read_target("${project}" "${encoded_configuration}" "${target}" target_json)

    # CMake normally folds INTERFACE usage requirements into the consumer's compile group, so INTERFACE targets do not
    # appear here as dependencies. Any target that does appear here must be an OBJECT library.
    _kontra_json_get(type target_json type)
    if(NOT type STREQUAL "OBJECT_LIBRARY")
        _kontra_fail(unsupported-target-type "reachable target '${target}' is '${type}'; kernel modules use OBJECT libraries")
    endif()

    # Mark the target before recursion so this walk is cycle-safe, even though CMake rejects OBJECT-library cycles.
    list(APPEND visited "${target}")

    # Sort dependencies so traversal order is stable.
    set(object_dependencies)
    _kontra_json_optional_indices(dependency_indices target_json dependencies)
    foreach(index IN LISTS dependency_indices)
        _kontra_json_get(dependency target_json dependencies "${index}")
        _kontra_json_get(id dependency id)
        _kontra_target_name_by_id("${project}" "${encoded_configuration}" "${id}" dependency_name)
        _kontra_record_backtrace_command(target_json dependency dependency_command)
        if(dependency_command STREQUAL "add_dependencies")
            _kontra_fail(
                unsupported-build-order-dependency
                "kernel target '${target}' has build-order dependency '${dependency_name}';"
                " add_dependencies() does not compose that target into the kernel module"
            )
        endif()
        _kontra_read_target("${project}" "${encoded_configuration}" "${dependency_name}" dependency_json)
        _kontra_json_get(dependency_type dependency_json type)
        if(NOT dependency_type STREQUAL "OBJECT_LIBRARY")
            _kontra_fail(
                unsupported-target-type
                "kernel target '${target}' reaches '${dependency_name}' of type '${dependency_type}';"
                " kernel dependencies must be OBJECT libraries"
            )
        endif()
        list(APPEND object_dependencies "${dependency_name}")
    endforeach()
    list(REMOVE_DUPLICATES object_dependencies)
    list(SORT object_dependencies)

    # Visit dependencies first.
    foreach(dependency_name IN LISTS object_dependencies)
        _kontra_visit_object_target(
            "${project}" "${encoded_configuration}" "${dependency_name}" "${visited}" "${order}"
            visited order
        )
    endforeach()

    # Append this target after its dependencies.
    list(APPEND order "${target}")
    set("${out_visited}" "${visited}" PARENT_SCOPE)
    set("${out_order}" "${order}" PARENT_SCOPE)
endfunction()

# Returns reachable object targets in stable postorder.
function(_kontra_object_target_order project encoded_configuration target out_order)
    _kontra_visit_object_target("${project}" "${encoded_configuration}" "${target}" "" "" visited order)
    set("${out_order}" "${order}" PARENT_SCOPE)
endfunction()

# Returns the source and build roots for a target.
function(_kontra_target_bases project encoded_configuration target out_source out_build)
    _kontra_file_api_target_index("${project}" "${encoded_configuration}" "${target}" index)
    _kontra_file_api_property("${project}" "${encoded_configuration}" TARGET_SOURCE_BASES source_bases)
    _kontra_file_api_property("${project}" "${encoded_configuration}" TARGET_BUILD_BASES build_bases)
    list(GET source_bases "${index}" source_path)
    list(GET build_bases "${index}" build_path)
    set("${out_source}" "${source_path}" PARENT_SCOPE)
    set("${out_build}" "${build_path}" PARENT_SCOPE)
endfunction()
