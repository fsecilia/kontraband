// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
// Copyright (c) 2026 Frank Secilia

#include "support.hpp"
#include <kontra_real/config.hpp>
#include <algorithm>
#include <limits>

static_assert(std::numeric_limits<unsigned int>::is_integer);
static_assert(std::min(20, 22) == 20);

namespace {

consteval auto real_value() noexcept -> int { return KONTRA_REAL_VALUE; }

} // namespace

extern "C" auto kontra_real_value(void) -> int { return real_value(); }
