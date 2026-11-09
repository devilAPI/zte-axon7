#!/vendor/bin/sh
# Load the kernel modules listed in /vendor/lib/modules/modules.load
# (BOARD_VENDOR_KERNEL_MODULES_LOAD) once /vendor is mounted, in order;
# modprobe pulls in dependencies from modules.dep.
d=/vendor/lib/modules
[ -r $d/modules.load ] || exit 0
/vendor/bin/modprobe -a -d $d $(grep -v '^#' $d/modules.load | sed 's/\.ko$//')
log -t axon7m-modules "loaded: $(wc -l < $d/modules.load) listed, rc $?"
