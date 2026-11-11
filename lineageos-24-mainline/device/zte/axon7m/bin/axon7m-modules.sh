#!/vendor/bin/sh
# Load the kernel modules listed in /vendor/lib/modules/modules.load
# (BOARD_VENDOR_KERNEL_MODULES_LOAD) once /vendor is mounted, in order;
# modprobe pulls in dependencies from modules.dep.
d=/vendor/lib/modules
[ -r $d/modules.load ] || exit 0
# init waits for this exec service: never let one stuck module hang the boot
timeout 60 /vendor/bin/modprobe -a -d $d $(grep -v '^#' $d/modules.load | sed 's/\.ko$//')
rc=$?
log -t axon7m-modules "loaded: $(wc -l < $d/modules.load) listed, rc $rc"
echo "axon7m-modules: $(wc -l < $d/modules.load) listed, rc $rc" > /dev/kmsg

# The QCA6174's PCIe link sometimes comes up only after qcom-pcie has given
# up at boot ("Device found, but not active", no wlan0; same on Nura, whose
# axon7-wifi-rescan.service does this): a bus rescan finds the chip.
dev=/sys/bus/pci/devices/0000:01:00.0
i=0
while [ ! -e $dev ] && [ $i -lt 5 ]; do
	echo 1 > /sys/bus/pci/rescan
	sleep 2
	i=$((i + 1))
done
if [ -e $dev ]; then
	echo "axon7m-modules: Wi-Fi chip on PCIe after $i rescan(s)" > /dev/kmsg
else
	echo "axon7m-modules: no Wi-Fi chip on PCIe after $i rescans" > /dev/kmsg
fi
