// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
// Copyright (c) 2026 Frank Secilia

#include <kontra_real/virtual.hpp>

namespace kontra {

auto value_source::value() const noexcept -> int { return -1; }
auto fixed_value_source::value() const noexcept -> int { return static_cast<int>(value_); }
auto read_value(value_source const& source) noexcept -> int { return source.value(); }

} // namespace kontra
