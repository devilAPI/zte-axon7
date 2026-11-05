#!/bin/sh
# Files in /boot changed (kernel or initramfs update): rebuild the
# postmarketOS half of the iOS + postmarketOS boot image. Never fails the
# apk transaction; the boot-time service retries if this ran too early.
/usr/libexec/axon7-dualboot-update || true
exit 0
