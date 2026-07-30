# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

# Unix Makefiles handles recursive Make differently from Ninja. CMake still decides whether unchecked targets are fresh,
# while checked builds must pass the outer GNU Make jobserver through to Kbuild.
kontra_copy_fixture(project source build)
set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel")
kontra_configure("${source}" "${build}" "${kernel}" "Unix Makefiles")
set(workspace "${build}/kontra/projects/kernel_project/modules/fixture_module/Release/workspace")

kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module.unchecked)
file(REMOVE "${workspace}/kbuild-invocations.txt")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module.unchecked)
if(EXISTS "${workspace}/kbuild-invocations.txt")
    message(FATAL_ERROR "unchanged unchecked Unix Makefiles build entered Kbuild")
endif()

file(REMOVE "${workspace}/fixture_output.ko")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module.unchecked)
kontra_assert_exists("${workspace}/fixture_output.ko")
file(STRINGS "${workspace}/kbuild-invocations.txt" invocations)
list(LENGTH invocations count)
if(NOT count EQUAL 1)
    message(FATAL_ERROR "missing module output did not re-enter Kbuild under Unix Makefiles")
endif()
file(REMOVE "${workspace}/kbuild-invocations.txt")

kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module -- -j4)
if(KONTRA_LAST_OUTPUT MATCHES "jobserver unavailable")
    message(FATAL_ERROR "checked Unix Makefiles build did not forward the GNU Make jobserver:\n${KONTRA_LAST_OUTPUT}")
endif()
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module -- -j4)
if(KONTRA_LAST_OUTPUT MATCHES "jobserver unavailable")
    message(FATAL_ERROR
        "repeated checked Unix Makefiles build did not forward the GNU Make jobserver:\n${KONTRA_LAST_OUTPUT}"
    )
endif()
file(STRINGS "${workspace}/kbuild-invocations.txt" invocations)
list(LENGTH invocations count)
if(NOT count EQUAL 2)
    message(FATAL_ERROR "checked Unix Makefiles target did not enter Kbuild on every build")
endif()

file(REMOVE "${workspace}/kbuild-invocations.txt")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module.unchecked)
if(EXISTS "${workspace}/kbuild-invocations.txt")
    message(FATAL_ERROR "checked build invalidated unchanged unchecked Unix Makefiles state")
endif()
