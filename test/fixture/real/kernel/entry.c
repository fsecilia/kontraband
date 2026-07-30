// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
// Copyright (c) 2026 Frank Secilia

#include <linux/init.h>
#include <linux/module.h>

int kontra_real_value(void);
int kontra_comdat_a(void);
int kontra_comdat_b(void);
int kontra_virtual_value(void);

static int __init kontra_real_init(void)
{
    if (kontra_real_value() != 37) return -EINVAL;
    if (kontra_comdat_a() + kontra_comdat_b() != 37) return -EINVAL;
    if (kontra_virtual_value() != 37) return -EINVAL;
    return 0;
}

static void __exit kontra_real_exit(void) {}
module_init(kontra_real_init);
module_exit(kontra_real_exit);
MODULE_LICENSE("Dual MIT/GPL");
