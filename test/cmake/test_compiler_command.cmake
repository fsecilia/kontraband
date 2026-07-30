# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")
kontra_copy_fixture(project source build)
set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel_command")

# The fake kernel reports `/usr/bin/env cc` as Kbuild's compiler command. If CMake identifies both nested languages, it
# received the required `cc` argument; `/usr/bin/env` alone is not a compiler. Do not inspect
# CMakeFiles/<version>/CMake*Compiler.cmake because that file is private and changes between CMake versions.
kontra_configure("${source}" "${build}" "${kernel}" Ninja)
set(linker_probe "${build}/kontra/projects/kernel_project/compiler-probe/linker.txt")
kontra_assert_contains("${linker_probe}" "/usr/bin/env ld")
set(cache "${build}/kontra/projects/kernel_project/subbuild/CMakeCache.txt")
kontra_assert_contains("${cache}" "CMAKE_C_COMPILER:FILEPATH=/usr/bin/env")
kontra_assert_contains("${cache}" "CMAKE_CXX_COMPILER:FILEPATH=/usr/bin/env")
kontra_assert_contains("${cache}" "CMAKE_C_COMPILER_ARG1:STRING= cc")
kontra_assert_contains("${cache}" "CMAKE_CXX_COMPILER_ARG1:STRING= cc")
kontra_assert_not_contains("${cache}" "CMAKE_TRY_COMPILE_TARGET_TYPE")
kontra_assert_contains(
    "${build}/kontra/projects/kernel_project/modules/fixture_module/Release/workspace/Kbuild"
    "cmd_cxx_o_cpp = \\$\\(CC\\)"
)
