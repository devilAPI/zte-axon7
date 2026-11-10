#!/vendor/bin/sh
# Bluetooth address: ZTE's factory address from persist/.bt_nv.bin (persist is
# mounted read-only, never written), else a static random address from the
# serial number LK passes (androidboot.serialno), as on Linaro's db845c.
s=$(/vendor/bin/cat /proc/cmdline | /vendor/bin/grep -o 'androidboot.serialno=[^ ]*' | /vendor/bin/cut -f2 -d=)
fb=$(echo "$s" | /vendor/bin/awk '{printf("c0%010s\n", substr($1, length($1) > 10 ? length($1) - 9 : 1))}' |
	/vendor/bin/tr ' ' 0 | /vendor/bin/sed 's/\(..\)/\1:/g; s/:$//')
exec /vendor/bin/hw/bdaddr --nv /mnt/vendor/persist/.bt_nv.bin "$fb"
