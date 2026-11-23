// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2026 Manufacturing Automation, LLC
/*
 * ccat_tcled - the "TC" front LED of the Beckhoff CX9240 as three Linux LED devices.
 *
 * The LED is driven by the CCAT FPGA GPIO function (type 0x0d) at 0xA0000300:
 *   +0x00 output value, bit 0 = red, bit 1 = green, bit 2 = blue
 *   +0x08 output enable (reads 0x07)
 * Found by experiment on one CX9240 (FPGA build 2026-07-02); not from Beckhoff documentation.
 */
#include <linux/module.h>
#include <linux/io.h>
#include <linux/leds.h>
#include <linux/spinlock.h>

#define TCLED_PHYS 0xA0000300UL
struct tcled { struct led_classdev cdev; u8 mask; };
static void __iomem *reg;
static DEFINE_SPINLOCK(lock);
static struct tcled leds[3] = {
	{ .cdev = { .name = "red:tc" },   .mask = 1 },
	{ .cdev = { .name = "green:tc" }, .mask = 2 },
	{ .cdev = { .name = "blue:tc" },  .mask = 4 },
};
static void tcled_set(struct led_classdev *c, enum led_brightness b)
{
	struct tcled *l = container_of(c, struct tcled, cdev); unsigned long f; u8 v;
	spin_lock_irqsave(&lock, f);
	v = ioread8(reg);
	v = b ? (v | l->mask) : (v & ~l->mask);
	iowrite8(v, reg);
	spin_unlock_irqrestore(&lock, f);
}
static enum led_brightness tcled_get(struct led_classdev *c)
{
	struct tcled *l = container_of(c, struct tcled, cdev);
	return (ioread8(reg) & l->mask) ? 1 : 0;
}
static int __init tcled_init(void)
{
	int i, ret;
	reg = ioremap(TCLED_PHYS, 0x10);
	if (!reg) return -ENOMEM;
	for (i = 0; i < 3; i++) {
		leds[i].cdev.max_brightness = 1;
		leds[i].cdev.brightness_set = tcled_set;
		leds[i].cdev.brightness_get = tcled_get;
		ret = led_classdev_register(NULL, &leds[i].cdev);
		if (ret) { while (i--) led_classdev_unregister(&leds[i].cdev); iounmap(reg); return ret; }
	}
	pr_info("ccat_tcled: TC LED registered (red:tc green:tc blue:tc)\n");
	return 0;
}
static void __exit tcled_exit(void)
{
	int i;
	for (i = 0; i < 3; i++) led_classdev_unregister(&leds[i].cdev);
	iounmap(reg);
}
module_init(tcled_init); module_exit(tcled_exit);
MODULE_DESCRIPTION("Beckhoff CX9240 TC front LED (CCAT GPIO)");
MODULE_LICENSE("GPL");
