#!/system/bin/sh
# Private, writable shadow of the modem's EFS images under /data.
#
# rmtfs -r serves EFS writes from a RAM shadow and drops them when the QRTR
# node changes (i.e. at every modem restart). MPSS expects those writes to
# survive its own restart; with -r it keeps repeating its 42 s init failure.
# Keeping the EFS images in /data lets rmtfs write them without ever writing
# the phone's modemst1/2, fsg or fsc partitions.
#
# Existing files are never overwritten: EFS state written by the modem must
# survive a reboot of Android as well. Called once from init (post-fs-data).
set -e
D=/data/vendor/axon7m-efs
mkdir -p "$D"
chmod 770 "$D"
for pair in modemst1:modem_fs1 modemst2:modem_fs2 fsg:modem_fsg fsc:modem_fsc; do
	src=/dev/block/by-name/${pair%%:*}
	dst=$D/${pair#*:}
	if [ ! -f "$dst" ]; then
		dd if="$src" of="$dst" bs=4096 2>/dev/null
		chmod 660 "$dst"
	fi
done
ls -l "$D" > /dev/null
