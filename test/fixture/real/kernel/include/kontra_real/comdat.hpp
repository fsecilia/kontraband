// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
// Copyright (c) 2026 Frank Secilia

#pragma once

namespace kontra {

template <typename value_t> [[gnu::noinline]] auto comdat_value(value_t value) noexcept -> value_t
{
    return value + static_cast<value_t>(1);
}

} // namespace kontra

extern "C" auto kontra_comdat_a(void) -> int;
extern "C" auto kontra_comdat_b(void) -> int;
