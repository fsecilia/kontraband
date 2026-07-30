// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
// Copyright (c) 2026 Frank Secilia

#pragma once

namespace kontra {

class value_source
{
public:
    virtual auto value() const noexcept -> int;
};

class fixed_value_source final : public value_source
{
public:
    explicit constexpr fixed_value_source(int value) noexcept : value_(value) {}
    auto value() const noexcept -> int override;

private:
    long value_;
};

auto read_value(value_source const& source) noexcept -> int;

} // namespace kontra

extern "C" auto kontra_virtual_value(void) -> int;
