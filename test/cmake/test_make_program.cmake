# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

# Kontraband needs GNU Make for Kbuild. If `make` is another implementation, GNU `gmake` is also accepted.
include("${KONTRA_TEST_PREFIX}/share/cmake/kontraband/detail/toolchain.cmake")
set(make_probe_directory "${KONTRA_TEST_CASE_ROOT}/make_probe")
file(MAKE_DIRECTORY "${make_probe_directory}")
file(WRITE "${make_probe_directory}/make" "#!/bin/sh\necho 'Not GNU Make'\n")
file(WRITE "${make_probe_directory}/gmake" "#!/bin/sh\necho 'GNU Make 4.4'\n")
file(CHMOD "${make_probe_directory}/make" "${make_probe_directory}/gmake"
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
)
set(saved_program_path "${CMAKE_PROGRAM_PATH}")
set(CMAKE_PROGRAM_PATH "${make_probe_directory}")
_kontra_resolve_make(resolved_make)
set(CMAKE_PROGRAM_PATH "${saved_program_path}")
if(NOT resolved_make STREQUAL "${make_probe_directory}/gmake")
    message(FATAL_ERROR "GNU gmake was not selected after rejecting non-GNU make: '${resolved_make}'")
endif()

# Nested configure must use the same Make executable selected by the outer generator.
kontra_copy_fixture(project source build)
set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel")
find_program(ninja_executable NAMES ninja REQUIRED)
set(wrapper "${KONTRA_TEST_CASE_ROOT}/custom-ninja")
file(WRITE "${wrapper}" "#!/bin/sh\nexec '${ninja_executable}' \"\$@\"\n")
file(CHMOD "${wrapper}"
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
)

kontra_run(
    "${CMAKE_COMMAND}" -S "${source}" -B "${build}" -G Ninja
    "-DCMAKE_MAKE_PROGRAM=${wrapper}"
    "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
    "-DFIXTURE_KERNEL_DIR=${kernel}"
    "-DCMAKE_BUILD_TYPE=Release"
)
file(STRINGS "${build}/kontra/projects/kernel_project/subbuild/CMakeCache.txt" make_program_line
    REGEX "^CMAKE_MAKE_PROGRAM:FILEPATH="
)
if(NOT make_program_line STREQUAL "CMAKE_MAKE_PROGRAM:FILEPATH=${wrapper}")
    message(FATAL_ERROR "nested CMAKE_MAKE_PROGRAM was not preserved: '${make_program_line}'")
endif()
