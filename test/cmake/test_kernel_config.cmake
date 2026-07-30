# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

# Do not make the compiler/linker matrix depend on the host's installed LLD version. The fixture only needs a program
# that accepts Kontraband's required linker test.
set(fake_bin "${KONTRA_TEST_CASE_ROOT}/fake-bin")
file(MAKE_DIRECTORY "${fake_bin}")
file(WRITE "${fake_bin}/ld.lld" "#!/bin/sh\nexit 0\n")
file(CHMOD "${fake_bin}/ld.lld" PERMISSIONS
    OWNER_READ OWNER_WRITE OWNER_EXECUTE
    GROUP_READ GROUP_EXECUTE
    WORLD_READ WORLD_EXECUTE
)
set(saved_path "$ENV{PATH}")
set(ENV{PATH} "${fake_bin}:$ENV{PATH}")

# Test one synthetic compiler/linker family reported by the kernel.
function(kontra_test_toolchain_case
    name cc_is_clang ld_is_lld expected_cc expected_ld expected_llvm expected_effective_cc expected_effective_ld
)
    set(case_root "${KONTRA_TEST_CASE_ROOT}/${name}")
    set(source "${case_root}/source")
    set(build "${case_root}/build")
    set(kernel "${case_root}/kernel")
    file(MAKE_DIRECTORY "${case_root}")
    file(COPY "${KONTRA_TEST_FIXTURE_ROOT}/project/" DESTINATION "${source}")
    file(COPY "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel_config/" DESTINATION "${kernel}")
    file(WRITE "${kernel}/include/config/auto.conf"
        "CONFIG_CC_IS_CLANG=${cc_is_clang}\nCONFIG_LD_IS_LLD=${ld_is_lld}\n"
    )

    kontra_configure("${source}" "${build}" "${kernel}" Ninja)
    set(probe_record "${build}/kontra/projects/kernel_project/compiler-probe/toolchain-arguments.txt")
    foreach(expected IN ITEMS
        "CC=${expected_cc}"
        "LD=${expected_ld}"
        "LLVM=${expected_llvm}"
        "EFFECTIVE_CC=${expected_effective_cc}"
        "EFFECTIVE_LD=${expected_effective_ld}"
    )
        kontra_assert_contains("${probe_record}" "${expected}")
    endforeach()

    kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module)
    set(workspace_record
        "${build}/kontra/projects/kernel_project/modules/fixture_module/Release/workspace/toolchain-arguments.txt"
    )
    foreach(expected IN ITEMS
        "CC=${expected_cc}"
        "LD=${expected_ld}"
        "LLVM=${expected_llvm}"
        "EFFECTIVE_CC=${expected_effective_cc}"
        "EFFECTIVE_LD=${expected_effective_ld}"
    )
        kontra_assert_contains("${workspace_record}" "${expected}")
    endforeach()
endfunction()

# GNU defaults need no derived selection.
kontra_test_toolchain_case(gcc-bfd n n cc ld "" cc ld)

# For a mixed toolchain, select the compiler and linker separately.
kontra_test_toolchain_case(clang-bfd y n clang ld "" clang ld)
kontra_test_toolchain_case(gcc-lld n y cc ld.lld "" cc ld.lld)

# LLVM=1 is used only when both compiler and linker are LLVM.
kontra_test_toolchain_case(clang-lld y y cc ld 1 clang ld.lld)

# auto.conf triggers outer reconfiguration. If the prepared kernel changes its recorded toolchain, the nested project
# must pick up the new compiler settings before the next build.
set(refresh_root "${KONTRA_TEST_CASE_ROOT}/refresh")
set(refresh_source "${refresh_root}/source")
set(refresh_build "${refresh_root}/build")
set(refresh_kernel "${refresh_root}/kernel")
file(MAKE_DIRECTORY "${refresh_root}")
file(COPY "${KONTRA_TEST_FIXTURE_ROOT}/project/" DESTINATION "${refresh_source}")
file(COPY "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel_config/" DESTINATION "${refresh_kernel}")
file(WRITE "${refresh_kernel}/include/config/auto.conf"
    "CONFIG_CC_IS_CLANG=n\nCONFIG_LD_IS_LLD=n\n"
)
kontra_configure("${refresh_source}" "${refresh_build}" "${refresh_kernel}" Ninja)
set(refresh_compiler_arg "${refresh_build}/kontra/projects/kernel_project/subbuild/compiler-arg.txt")
kontra_assert_contains("${refresh_compiler_arg}" "FAKE_CC=cc")

file(WRITE "${refresh_kernel}/include/config/auto.conf"
    "CONFIG_CC_IS_CLANG=y\nCONFIG_LD_IS_LLD=y\n"
)
kontra_run("${CMAKE_COMMAND}" --build "${refresh_build}" --target kernel_project.fixture_module)
kontra_assert_contains("${refresh_compiler_arg}" "FAKE_CC=clang")
set(refresh_probe "${refresh_build}/kontra/projects/kernel_project/compiler-probe/toolchain-arguments.txt")
kontra_assert_contains("${refresh_probe}" "LLVM=1")

set(ENV{PATH} "${saved_path}")

# Kernel auto-selection skips installed kernels whose build symlink does not resolve to a directory.
include("${KONTRA_TEST_PREFIX}/share/cmake/kontraband/detail/toolchain.cmake")
set(modules_root "${KONTRA_TEST_CASE_ROOT}/installed-modules")
file(MAKE_DIRECTORY "${modules_root}/usable/build" "${modules_root}/stale")
file(CREATE_LINK "${modules_root}/missing-build" "${modules_root}/stale/build" SYMBOLIC RESULT link_result)
if(NOT link_result STREQUAL "0")
    message(FATAL_ERROR "could not create dangling kernel build symlink: ${link_result}")
endif()
_kontra_installed_kernel_build_directories("${modules_root}" installed_builds)
if(NOT installed_builds STREQUAL "${modules_root}/usable/build")
    message(FATAL_ERROR "kernel build candidate filtering returned '${installed_builds}'")
endif()

# Kbuild paths may contain non-ASCII characters. Validation rejects unsafe Make syntax, not names outside English.
set(unicode_root "${KONTRA_TEST_CASE_ROOT}/unicode-kernel-path")
set(unicode_source "${unicode_root}/source")
set(unicode_build "${unicode_root}/build")
set(unicode_kernel "${unicode_root}/内核")
file(COPY "${KONTRA_TEST_FIXTURE_ROOT}/project/" DESTINATION "${unicode_source}")
file(COPY "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel/" DESTINATION "${unicode_kernel}")
kontra_configure("${unicode_source}" "${unicode_build}" "${unicode_kernel}" Ninja)
kontra_run("${CMAKE_COMMAND}" --build "${unicode_build}" --target kernel_project.fixture_module.unchecked)
