# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2026 Manufacturing Automation, LLC
obj-m += ccat.o ccat_netdev.o ccat_cx_shim.o ccat_tcled.o
ccat-y := module.o
ccat_netdev-y := netdev.o
KDIR ?= /lib/modules/$(shell uname -r)/build
all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
