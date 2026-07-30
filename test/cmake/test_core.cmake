# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

# This is the main successful fixture. It covers the resolved toolchain, graph flattening, option attribution, generated
# Kbuild files, stable export, and checked/unchecked builds in one ordinary project.
kontra_copy_fixture(project source build)
set(kernel "${KONTRA_TEST_CASE_ROOT}/kernel")
file(COPY "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel/" DESTINATION "${kernel}")
kontra_configure("${source}" "${build}" "${kernel}" Ninja)
if(NOT KONTRA_LAST_OUTPUT MATCHES "CMake Warning" OR
   NOT KONTRA_LAST_OUTPUT MATCHES "'-DFIXTURE_GLOBAL_CXX_FLAG=1'" OR
   NOT KONTRA_LAST_OUTPUT MATCHES "'-fPIC'" OR
   NOT KONTRA_LAST_OUTPUT MATCHES "'-Werror'" OR
   NOT KONTRA_LAST_OUTPUT MATCHES "'-fvisibility=hidden'" OR
   NOT KONTRA_LAST_OUTPUT MATCHES "'-fvisibility-inlines-hidden'" OR
   NOT KONTRA_LAST_OUTPUT MATCHES "Kontraband\\[unprojected-compiler-option\\]" OR
   NOT KONTRA_LAST_OUTPUT MATCHES "will not be used when the kernel module is compiled")
    message(FATAL_ERROR "configure did not warn with the discarded unattributed compiler options:\n${KONTRA_LAST_OUTPUT}")
endif()

# The nested C/C++ project must use Kbuild's compiler command. Generated Kbuild should keep only explicit target options
# plus the C++ flags Kontraband requires. The fixture's unattributed global flags must not leak through.
set(nested_cache "${build}/kontra/projects/kernel_project/subbuild/CMakeCache.txt")
kontra_assert_contains("${nested_cache}" "CMAKE_C_COMPILER:FILEPATH=.*/cc")
kontra_assert_contains("${nested_cache}" "CMAKE_CXX_COMPILER:FILEPATH=.*/cc")
if(KONTRA_LAST_OUTPUT MATCHES "CMAKE_ASM_COMPILER")
    message(FATAL_ERROR "C/C++-only nested configure reported an unused assembler setting:\n${KONTRA_LAST_OUTPUT}")
endif()

set(kbuild "${build}/kontra/projects/kernel_project/modules/fixture_module/Release/workspace/Kbuild")
set(probe_kbuild "${build}/kontra/projects/kernel_project/compiler-probe/Kbuild")
kontra_assert_contains("${kbuild}" "cmd_cxx_o_cpp = \\$\\(CC\\)")
kontra_assert_contains("${kbuild}" "kontra_required_kbuild_symbols")
kontra_assert_contains("${kbuild}" "CC_FLAGS_FTRACE")
kontra_assert_contains("${kbuild}" "-DCC_USING_%")
kontra_assert_contains("${kbuild}" "-std=%")
kontra_assert_contains("${probe_kbuild}" "kontra_required_kbuild_symbols")

kontra_assert_contains("${kbuild}" "fixture_output-y := .*alpha.o.*beta.o.*core.o.*zeta.o.*entry.o.*bridge.impl.o")
kontra_assert_contains("${kbuild}" "-DFIXTURE_CORE=1")
kontra_assert_contains("${kbuild}" "-DFIXTURE_INTERFACE=1")
kontra_assert_contains("${kbuild}" "-DFIXTURE_CXX_OPTION=1")

kontra_assert_not_contains("${kbuild}" "FIXTURE_GLOBAL_CXX_FLAG")
kontra_assert_not_contains("${kbuild}" "'-fPIC'")
kontra_assert_not_contains("${kbuild}" "'-fvisibility")
kontra_assert_not_contains("${kbuild}" "'-Werror'")
kontra_assert_not_contains("${build}/CMakeCache.txt" "_kontra_make_candidate:FILEPATH=")

# The same resolved graph must produce the same Kbuild text after reconfiguration and in a separate build directory.
# Source order must not depend on traversal order or incidental filesystem order.
file(READ "${kbuild}" deterministic_kbuild)
foreach(iteration RANGE 1 8)
    kontra_configure("${source}" "${build}" "${kernel}" Ninja)
    file(READ "${kbuild}" reconfigured_kbuild)
    if(NOT reconfigured_kbuild STREQUAL deterministic_kbuild)
        message(FATAL_ERROR "no-op configure ${iteration} changed generated Kbuild")
    endif()
endforeach()

set(fresh_build_a "${KONTRA_TEST_CASE_ROOT}/fresh-a")
set(fresh_build_b "${KONTRA_TEST_CASE_ROOT}/fresh-b")
kontra_configure("${source}" "${fresh_build_a}" "${kernel}" Ninja)
kontra_configure("${source}" "${fresh_build_b}" "${kernel}" Ninja)
file(READ
    "${fresh_build_a}/kontra/projects/kernel_project/modules/fixture_module/Release/workspace/Kbuild"
    fresh_kbuild_a
)
file(READ
    "${fresh_build_b}/kontra/projects/kernel_project/modules/fixture_module/Release/workspace/Kbuild"
    fresh_kbuild_b
)
if(NOT fresh_kbuild_a STREQUAL fresh_kbuild_b)
    message(FATAL_ERROR "fresh build directories produced different Kbuild files")
endif()

# Build once to create the module and workspace before testing checked and unchecked freshness.
set(workspace "${build}/kontra/projects/kernel_project/modules/fixture_module/Release/workspace")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module.unchecked)
kontra_assert_exists("${workspace}/fixture_output.ko")
if(NOT IS_SYMLINK "${workspace}/projection/kernel/bridge_impl.cpp")
    message(FATAL_ERROR "development source view is not symlinked")
endif()

# Checked builds always enter Kbuild.
file(REMOVE "${workspace}/kbuild-invocations.txt")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module)
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module)
file(STRINGS "${workspace}/kbuild-invocations.txt" invocations)
list(LENGTH invocations count)
if(NOT count EQUAL 2)
    message(FATAL_ERROR "checked target should enter Kbuild on every explicit build")
endif()

# Unchecked builds only react to dependencies visible to the outer CMake graph.
file(REMOVE "${workspace}/kbuild-invocations.txt")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module.unchecked)
if(NOT KONTRA_LAST_OUTPUT MATCHES "no work to do")
    message(FATAL_ERROR "unchanged unchecked build was not inert:\n${KONTRA_LAST_OUTPUT}")
endif()

# The unchecked target still depends on the module file itself.
file(REMOVE "${workspace}/fixture_output.ko")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module.unchecked)
kontra_assert_exists("${workspace}/fixture_output.ko")
file(STRINGS "${workspace}/kbuild-invocations.txt" invocations)
list(LENGTH invocations count)
if(NOT count EQUAL 1)
    message(FATAL_ERROR "missing module output should enter Kbuild exactly once through unchecked target")
endif()
file(REMOVE "${workspace}/kbuild-invocations.txt")

# Declared support files can make the unchecked target stale even when Kbuild does not compile them directly.
kontra_run("${CMAKE_COMMAND}" -E sleep 1)
file(TOUCH "${source}/kernel/unused.hpp")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module.unchecked)
file(STRINGS "${workspace}/kbuild-invocations.txt" invocations)
list(LENGTH invocations count)
if(NOT count EQUAL 1)
    message(FATAL_ERROR "changed declared header should enter Kbuild exactly once through unchecked target")
endif()
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module.unchecked)
if(NOT KONTRA_LAST_OUTPUT MATCHES "no work to do")
    message(FATAL_ERROR "post-header-change unchecked build was not inert")
endif()

# The unchecked target cannot see a dependency that exists only inside Kbuild.
file(WRITE "${kernel}/hidden-header.h" "first\n")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module)
file(REMOVE "${workspace}/kbuild-invocations.txt")
kontra_run("${CMAKE_COMMAND}" -E sleep 1)
file(APPEND "${kernel}/hidden-header.h" "second\n")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module.unchecked)
if(NOT KONTRA_LAST_OUTPUT MATCHES "no work to do")
    message(FATAL_ERROR "unchecked target unexpectedly tracked an undeclared Kbuild-only dependency")
endif()
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module)
file(STRINGS "${workspace}/kbuild-invocations.txt" invocations)
list(LENGTH invocations count)
if(NOT count EQUAL 1)
    message(FATAL_ERROR "checked target did not enter Kbuild after a Kbuild-only change")
endif()

# Project and global aggregates both provide checked and unchecked targets.
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.unchecked)
set(aux_workspace "${build}/kontra/projects/kernel_project/modules/fixture_aux/Release/workspace")
kontra_assert_exists("${aux_workspace}/fixture_aux.ko")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kontra_kernel_modules.unchecked)
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kontra_kernel_modules)

# Project clean runs each module's clean target and removes both Kbuild outputs and unchecked stamps.
kontra_assert_exists("${workspace}/fixture_output.ko")
kontra_assert_exists("${aux_workspace}/fixture_aux.ko")
kontra_assert_exists("${build}/kontra/projects/kernel_project/modules/fixture_module/Release/state/unchecked.stamp")
kontra_assert_exists("${build}/kontra/projects/kernel_project/modules/fixture_aux/Release/state/unchecked.stamp")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.clean)
kontra_assert_not_exists("${workspace}/fixture_output.ko")
kontra_assert_not_exists("${aux_workspace}/fixture_aux.ko")
kontra_assert_not_exists("${build}/kontra/projects/kernel_project/modules/fixture_module/Release/state/unchecked.stamp")
kontra_assert_not_exists("${build}/kontra/projects/kernel_project/modules/fixture_aux/Release/state/unchecked.stamp")

# Global clean runs every kernel project's clean target. Rebuild through the global unchecked target first so module
# outputs and unchecked stamps both exist, then check that global clean removes them.
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kontra_kernel_modules.unchecked)
kontra_assert_exists("${workspace}/fixture_output.ko")
kontra_assert_exists("${aux_workspace}/fixture_aux.ko")
kontra_assert_exists("${build}/kontra/projects/kernel_project/modules/fixture_module/Release/state/unchecked.stamp")
kontra_assert_exists("${build}/kontra/projects/kernel_project/modules/fixture_aux/Release/state/unchecked.stamp")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kontra_kernel_modules.clean)
kontra_assert_not_exists("${workspace}/fixture_output.ko")
kontra_assert_not_exists("${aux_workspace}/fixture_aux.ko")
kontra_assert_not_exists("${build}/kontra/projects/kernel_project/modules/fixture_module/Release/state/unchecked.stamp")
kontra_assert_not_exists("${build}/kontra/projects/kernel_project/modules/fixture_aux/Release/state/unchecked.stamp")
