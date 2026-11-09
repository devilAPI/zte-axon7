#!/bin/bash
# Report every option of an Android config fragment that did not end up in the
# final kernel .config as requested (missing symbol, unmet dependency, or a
# value Kconfig changed).  Exit status 0 even with mismatches: some are
# expected (see the list printed at the end); read the report.
#
# Usage: kernel-config-check.sh OUT/.config FRAGMENT
cfg=$1 frag=$2
[ -r "$cfg" ] && [ -r "$frag" ] || { echo "usage: $0 .config fragment" >&2; exit 2; }
bad=0
while IFS= read -r line; do
	case "$line" in
	CONFIG_*=*)
		sym=${line%%=*}; want=${line#*=} ;;
	"# CONFIG_"*" is not set")
		sym=${line#\# }; sym=${sym%% *}; want=n ;;
	*) continue ;;
	esac
	have=$(grep -E "^$sym=" "$cfg" | head -1 | cut -d= -f2-)
	[ -z "$have" ] && have=n
	if [ "$have" != "$want" ]; then
		printf '  %-45s want %-10s have %s\n' "$sym" "$want" "$have"
		bad=$((bad + 1))
	fi
done < "$frag"
echo "config check: $bad option(s) differ from $(basename "$frag")"
exit 0
