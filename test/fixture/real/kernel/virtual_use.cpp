// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
// Copyright (c) 2026 Frank Secilia

#include <kontra_real/virtual.hpp>

extern "C" auto kontra_virtual_value(void) -> int
{
    kontra::fixed_value_source source{37};
    return kontra::read_value(source);
}
