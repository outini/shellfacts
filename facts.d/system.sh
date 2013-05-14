#! /bin/sh

PATH=$PATH:/sbin

[ "$DEBUG" = "true" ] || DEBUG=false

init_infos() {
    HOSTNAME=`hostname` || \
	echo "[ERROR] unable to get hostname"
    HOSTFQDN=`hostname -f || { echo -n "${HOSTNAME}."; domainname; }` || \
	echo "[ERROR] unable to get hostfqdn"
    KERNEL=`uname -r` || \
	echo "[ERROR] unable to get kernel release"
    OS=`uname -o || uname -s` || \
	echo "[ERROR] unable to get operating system"
    CPUINFOS=`cat /proc/cpuinfo` || \
	echo "[ERROR] unable to get cpus informations"
    MEMINFOS=`free` || \
	echo "[ERROR] unable to get memory informations"
    SYSCTLINFOS=`sysctl -a` || \
	echo "[ERROR] unable to get sysctl informations"
}

get_common_sysfacts() {
    echo "system_commons:"
    echo "  hostname: $HOSTNAME"
    echo "  hostfqdn: $HOSTFQDN"
    echo "  kernel_release: $KERNEL"
    echo "  operating_system: $OS"
}

get_cpus_sysfacts() {
    [ -z "$CPUINFOS" ] ||
    echo "$CPUINFOS" | awk -F": " '
BEGIN { print "system_cpus:" }

/^processor/ { print "- cpu_id: " $2 }
/^vendor_id/ { print "  cpu_vendor: " $2 }
/^model name/ { gsub(/[ \t]+/, " ", $2); print "  cpu_model: " $2 }
/^cpu MHz/ { print "  cpu_speed: " $2 }
/^cache size/ { print "  cpu_cache: " $2 }
/^flags/ {
    print "  cpu_flags:"
    split($2, cpu_flags, / /)
    for (i in cpu_flags) print "  - " cpu_flags[i]
}
'
}

get_mem_sysfacts() {
    [ -z "$MEMINFOS" ] ||
    echo "$MEMINFOS" | awk -v "OS=$OS" '
BEGIN { print "system_memory:" }

/^Mem/ {
    print "  memory_total: " $2
    print "  memory_used: " $3
    print "  memory_free: " $4
    if (OS ~ /Linux/) memory_buffers = $6
    else memory_buffers = $5
    print "  memory_buffers: " memory_buffers
    printf("  memory_usage: %.1f%%\n", memory_buffers * 100 / $2)
}
/^Swap:/ {
    print "  swap_total: " $2
    print "  swap_used: " $3
    print "  swap_free: " $4
    printf("  swap_usage: %.1f%%\n", $3 * 100 / $2)
}
'
}

get_sysctl_sysfacts() {
    [ -z "$SYSCTLINFOS" ] ||
    echo "$SYSCTLINFOS" |
    awk -F: '
function join(array, start, end, sep) {
  result = array[start]
  for (i = start + 1; i <= end; i++)
    result = result sep array[i]
  return result
}

{
  if ($1 !~ /^#### .* ####$/) {

    # for nested entries like:
    #  kern.cp_time: user = 120254668, nice = 8745
    if ($0 ~ /^[^= ]+:/) {
      values = $0
      gsub(/ =/, ":", values)
      gsub(/^[^:]+: /, "", values)
      sysctl_array[sysctl_index++] = sprintf("%s: {%s}", $1, values)
      next
    }

    len = split($0, array, " = ")

    # for multi-lines entries, if line does not contain "=", add to previous
    if (len < 2) {
      gsub(/"$/, "", sysctl_array[sysctl_index-1])
      sysctl_array[sysctl_index-1] = sprintf("%s%s\"", sysctl_array[sysctl_index-1], array[1])
    } else {
      sysctl_array[sysctl_index++] = sprintf("%s: \"%s\"", array[1], array[2])
    }
  }
}

END {
  printf("sysctl: {%s}\n", join(sysctl_array, 0, sysctl_index-1, ", "))
}
'
}


# while [ $# -gt 0 ]; do
#     case "$1" in
#         *) echo "unknown arg: $1"; shift ;;
#     esac
# done

#echo "#### BEGIN MEM FACTS ####"
#free
#echo "#### END CPUS FACTS ####"

#echo "#### BEGIN SYSCTL FACTS ####"
#sysctl -a
#echo "#### END SYSCTL FACTS ####"

init_infos 2>/dev/null
get_common_sysfacts
get_cpus_sysfacts
get_mem_sysfacts
get_sysctl_sysfacts