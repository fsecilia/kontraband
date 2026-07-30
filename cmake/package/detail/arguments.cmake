# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

# Rejects compiler arguments that cannot be written safely in generated Make syntax.
function(_kontra_validate_argument token context)
    if(token STREQUAL "" OR token MATCHES "[;\r\n]")
        _kontra_fail(unsupported-compiler-argument "${context} contains unsupported argument '${token}'")
    endif()
endfunction()

# Quotes one generated Make token for the shell with single quotes.
function(_kontra_quote_single_argument token escape_dollar out_token)
    set(encoded "${token}")
    if(escape_dollar)
        string(REPLACE "$" "$$" encoded "${encoded}")
    endif()

    # GNU Make removes one backslash before '#'. Double the existing backslashes first so the original text survives.
    string(REGEX REPLACE [=[(\\*)#]=] [=[\1\1\\#]=] encoded "${encoded}")
    string(REPLACE "'" "'\"'\"'" encoded "${encoded}")

    set("${out_token}" "'${encoded}'" PARENT_SCOPE)
endfunction()

# Quotes one compiler argument so generated Make syntax passes it unchanged to the shell.
function(_kontra_quote_shell_argument token context out_token)
    _kontra_validate_argument("${token}" "${context}")
    _kontra_quote_single_argument("${token}" TRUE encoded)
    set("${out_token}" "${encoded}" PARENT_SCOPE)
endfunction()

# Quotes one Make expression without escaping dollar signs such as $(src).
function(_kontra_quote_make_argument token context out_token)
    _kontra_validate_argument("${token}" "${context}")
    _kontra_quote_single_argument("${token}" FALSE encoded)
    set("${out_token}" "${encoded}" PARENT_SCOPE)
endfunction()

# Quotes one saved Kbuild assignment while keeping semicolons as literal text.
function(_kontra_quote_kbuild_argument token out_token)
    if(token STREQUAL "" OR token MATCHES "[\r\n]")
        _kontra_fail(unsupported-kbuild-argument "KBUILD_ARGUMENTS contains unsupported argument '${token}'")
    endif()
    _kontra_quote_single_argument("${token}" TRUE encoded)
    set("${out_token}" "${encoded}" PARENT_SCOPE)
endfunction()

# Quotes and joins persistent Kbuild assignments for generated Make syntax.
function(_kontra_quote_kbuild_arguments arguments out_text)
    set(quoted_arguments)
    foreach(argument IN LISTS arguments)
        _kontra_quote_kbuild_argument("${argument}" quoted_argument)
        _kontra_append_opaque_list_value(quoted_arguments "${quoted_argument}")
    endforeach()
    list(JOIN quoted_arguments " " text)
    set("${out_text}" "${text}" PARENT_SCOPE)
endfunction()
