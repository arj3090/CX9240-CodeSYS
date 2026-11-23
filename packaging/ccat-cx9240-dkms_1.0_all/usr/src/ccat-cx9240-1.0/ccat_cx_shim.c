// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2026 Manufacturing Automation, LLC
// CX9240 shim: registers a platform_device named "ccat" so the (patched)
// platform/EIM driver in ccat.ko binds and runs ccat_functions_init against
// the live CCAT at 0xA0000000. No OF node / overlay needed; name-matches the
// driver. Load order: insmod ccat.ko ; insmod ccat_cx_shim.ko.
#include <linux/module.h>
#include <linux/platform_device.h>

static struct platform_device *cx_pdev;

static int __init ccat_cx_shim_init(void)
{
	cx_pdev = platform_device_register_simple("ccat", -1, NULL, 0);
	if (IS_ERR(cx_pdev)) {
		pr_err("ccat_cx_shim: register failed: %ld\n", PTR_ERR(cx_pdev));
		return PTR_ERR(cx_pdev);
	}
	pr_info("ccat_cx_shim: registered platform_device 'ccat'\n");
	return 0;
}

static void __exit ccat_cx_shim_exit(void)
{
	platform_device_unregister(cx_pdev);
	pr_info("ccat_cx_shim: unregistered\n");
}

module_init(ccat_cx_shim_init);
module_exit(ccat_cx_shim_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("CX9240 CCAT platform-device shim");
