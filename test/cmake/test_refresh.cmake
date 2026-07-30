# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")
kontra_copy_fixture(project source build)
set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel")

# Change fixture text only if the expected original text is present. If the fixture is reformatted, fail instead of
# quietly editing the wrong text.
function(kontra_replace_required input match replacement out_value)
    string(FIND "${input}" "${match}" offset)
    if(offset EQUAL -1)
        message(FATAL_ERROR "required refresh-fixture text was not found: '${match}'")
    endif()
    string(REPLACE "${match}" "${replacement}" value "${input}")
    set("${out_value}" "${value}" PARENT_SCOPE)
endfunction()
kontra_configure("${source}" "${build}" "${kernel}" Ninja)
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module)

file(WRITE "${source}/include/fixture/new.hpp" "#pragma once\n")
file(READ "${source}/config.cmake" config)
kontra_replace_required(
    "${config}"
    [=["${root}/include/fixture/core.hpp"]=]
    [=["${root}/include/fixture/core.hpp"
        "${root}/include/fixture/new.hpp"]=]
    config
)
file(WRITE "${source}/config.cmake" "${config}")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module)
set(workspace "${build}/kontra/projects/kernel_project/modules/fixture_module/Release/workspace")
if(NOT IS_SYMLINK "${workspace}/projection/include/fixture/new.hpp")
    message(FATAL_ERROR "newly declared file was not added to workspace")
endif()

# Reconfiguration must preserve non-ASCII projection paths exactly. Removing the only file should also remove its
# empty parent.
file(READ "${source}/config.cmake" config)
kontra_replace_required(
    "${config}" [=[        "${root}/include/fixture/café/support.txt"
]=] "" config
)
file(WRITE "${source}/config.cmake" "${config}")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module)
kontra_assert_not_exists("${workspace}/projection/include/fixture/café")

file(READ "${source}/config.cmake" config)
kontra_replace_required(
    "${config}" [=[        "${root}/include/fixture/obsolete/only.hpp"
]=] "" config
)
file(WRITE "${source}/config.cmake" "${config}")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module)
kontra_assert_not_exists("${workspace}/projection/include/fixture/obsolete")
