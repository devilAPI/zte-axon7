/* Test-only helper: apply the IPA DT overlay in the running kernel. */
#define pr_fmt(fmt) "ipa-dt-test: " fmt
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include "ipa-overlay.h"

static int ovcs_id = -1;

static int __init ipa_dt_test_init(void)
{
	int ret = of_overlay_fdt_apply(ipa_ovl, ipa_ovl_len, &ovcs_id, NULL);

	pr_info("apply ret=%d ovcs_id=%d\n", ret, ovcs_id);
	return ret;
}

static void __exit ipa_dt_test_exit(void)
{
	pr_info("remove ret=%d\n", of_overlay_remove(&ovcs_id));
}

module_init(ipa_dt_test_init);
module_exit(ipa_dt_test_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Temporary IPA DT overlay for the Axon 7 test");
