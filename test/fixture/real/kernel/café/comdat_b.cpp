// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
// Copyright (c) 2026 Frank Secilia

#include <kontra_real/comdat.hpp>

extern "C" auto kontra_comdat_b(void) -> int { return kontra::comdat_value<int>(17); }
