#! /bin/sh

[ "$DEBUG" = "true" ] || DEBUG=false

XM_INFO="`xm info 2>/dev/null`"
XM_LIST="`xm list 2>/dev/null`"

[ -z "$XM_INFO" ] && exit 0
[ -z "$XM_LIST" ] && exit 0

xen_total_vcpus=`echo "$XM_INFO" | awk '/nr_cpus/{ print $3 }'`
xen_used_vcpus=`echo "$XM_LIST" | awk 'NR>1 { sum+=$4 } END { print sum }'`
xen_free_vpus=$(($xen_total_vcpus - ${xen_used_vcpus:-0}))

die() {
    echo "$@" >&2
    exit 2
}
get_dom0_caps_full() {
    awk '{
          if ($1 == "nr_cpus") { vcpus=$3 }
          if ($1 == "total_memory") { total_mem=$3 }
          if ($1 == "free_memory") { free_mem=$3 }
         }END{
          printf("xen_dom0_caps: {free_vcpus: %d, total_vcpus: %d, free_memory: %d, total_memory: %d}\n",'$xen_free_vpus',vcpus,free_mem,total_mem)
         }'
}
get_dom0_caps_light() {
    awk '/total_memory/{ print "xen_total_memory: "$3 }
         /free_memory/{ print "xen_free_memory: "$3 }' "$@"
    echo "xen_free_vcpus: $xen_free_vpus"
    echo "xen_total_vcpus: $xen_total_vcpus"
}
get_dom0_caps() {
    echo "$XM_INFO" | "${FUNCNAME}_$1"
}

get_domus_usage_full() {
    awk 'BEGIN { domus_count=0 } NR > 1 {
          name=$1
          mem=$3
          vcpus=$4

          if (name ~ Domain-0) {
            domain0 = sprintf("{name: %s, vcpus: %d, memory: %d}",
                              name, vcpus, mem)
          } else {
            config_fn = sprintf("/etc/xen/%s.cfg", name)
            auto_fn = sprintf("/etc/xen/auto/%s.cfg", name)
            auto = config = "false"

            if ((getline < config_fn) > 0) { close(config_fn); config = "true" }
            if ((getline < auto_fn) > 0) { close(auto_fn); auto = "true" }

            domus[i++] = sprintf("{name: %s, vcpus: %d, memory: %d, auto: %s, config: %s}", name, vcpus, mem,auto, config)

            mem_sum+=mem
            cpu_sum+=vcpus
            domus_count++
          }
         }END{
          domus_yaml = domus[0]
          for (j = 1; j < i; j++) domus_yaml = domus_yaml ", " domus[j]
          summary = sprintf("{count: %d, total_cpu: %d, total_memory: %d}", domus_count, cpu_sum, mem_sum)

          printf("domus: {domain0: %s, hosts: [%s], summary: %s}\n", domain0, domus_yaml, summary)
         }' "$@"
}
get_domus_usage_light() {
    awk 'NR > 2 { print "domu_"$1": true" }' "$@"
}
get_domus_usage() {
    echo "$XM_LIST" | "${FUNCNAME}_$1"
}

[ "`whoami`" = "root" ] || die "you must be root"

while [ $# -gt 0 ]; do
    case "$1" in
	# force refresh can be requested via cli but is ignored here
	force-refresh) shift ;;
	light|full) details="$1"; shift ;;
	*) echo "unknown arg: $1"; shift ;;
    esac
done
[ -z "$details" ] && details=light

get_dom0_caps $details
get_domus_usage $details
