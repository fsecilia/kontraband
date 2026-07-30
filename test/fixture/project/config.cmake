# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

# Apply shared fixture sources and usage requirements to one host or nested target.
function(fixture_configure_core target)
    set(root "${CMAKE_CURRENT_FUNCTION_LIST_DIR}")
    target_sources("${target}" PRIVATE
        "${root}/src/core.cpp"
        "${root}/include/fixture/core.hpp"
        "${root}/include/fixture/café/support.txt"
        "${root}/include/fixture/obsolete/only.hpp"
        "${root}/include/fixture/executable_helper.sh"
    )
    target_include_directories("${target}" PUBLIC "${root}/include")
    target_compile_definitions("${target}" PUBLIC FIXTURE_CORE=1)
    target_compile_features("${target}" PUBLIC cxx_std_20)
endfunction()
