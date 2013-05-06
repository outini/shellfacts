#! /bin/sh

PATH=$PATH:/sbin

[ "$DEBUG" = "true" ] || DEBUG=false

display_system_facts_light() {
    awk -F: '
/#### BEGIN GENERIC FACTS ####/,/#### END GENERIC FACTS ####/ {
  if ($1 !~ /^#### .* ####$/) { printf("%s: %s\n", $1, $2) }
}

/#### BEGIN CPUS FACTS ####/,/#### END CPUS FACTS ####/ {
  if ($1 ~ /model name/) { cpu_model = $2; cpu_count++ }
}

/#### BEGIN MEM FACTS ####/,/#### END MEM FACTS ####/ {
  if ($1 ~ /Mem/) { mem_size = $2 }
  else if ($1 ~ /Swap/) { swap_size = $2 }
}

END {
  printf("cpu_model: %s\ncpu_count: %d\n", cpu_model, cpu_count)
  printf("memory: %d\nswap: %d\n", mem_size, swap_size)
}
'
}
display_system_facts_full() {
    awk -F: '
function join(array, start, end, sep) {
  result = array[start]
  for (i = start + 1; i <= end; i++)
    result = result sep array[i]
  return result
}

/#### BEGIN GENERIC FACTS ####/,/#### END GENERIC FACTS ####/ {
  if ($1 !~ /^#### .* ####$/) { printf("%s: %s\n", $1, $2) }
}

/#### BEGIN CPUS FACTS ####/,/#### END CPUS FACTS ####/ {
  if ($1 ~ /model name/) { cpu_model = $2; cpu_count++ }
  else if ($1 ~ /cpu MHz/) { cpu_speed = $2 }
}

/#### BEGIN MEM FACTS ####/,/#### END MEM FACTS ####/ {
  if ($1 ~ /Mem/) { mem_size = $2 }
  else if ($1 ~ /buffers/) { mem_buffers = $2 }
  else if ($1 ~ /Swap/) { swap_size = $2; swap_use = $3 }
}

/#### BEGIN SYSCTL FACTS ####/,/#### END SYSCTL FACTS ####/ {
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

  printf("cpu_infos: {model: %s, speed: %s, count: %d}\n",
         cpu_model, cpu_speed, cpu_count)

  mem_usage = mem_buffers * 100 / mem_size
  swap_usage = swap_use * 100 / swap_size
  mem_line = sprintf("total: %d, buffers: %d, usage: %.1f",
                     mem_size, mem_buffers, mem_usage)
  swap_line = sprintf("swap_total: %d, swap_use: %d, swap_usage: %.1f",
                      swap_size, swap_use, swap_usage)
  printf("memory_infos: {%s, %s}\n", mem_line, swap_line)
}
'
}


while [ $# -gt 0 ]; do
    case "$1" in
        # force refresh can be requested via cli but is ignored here
        force-refresh) shift ;;
        light|full) details="$1"; shift ;;
        *) echo "unknown arg: $1"; shift ;;
    esac
done
[ -z "$details" ] && details=light

{
echo "#### BEGIN GENERIC FACTS ####"
hostname=`hostname` && echo "hostname:$hostname"
hostfqdn=`hostname -f` echo "hostfqdn:$hostfqdn"
kernel=`uname -r` && echo "kernel_release:$kernel"
os=`uname -o` && echo "operating_system:$os"
echo "#### END GENERIC FACTS ####"

echo "#### BEGIN CPUS FACTS ####"
cat /proc/cpuinfo
echo "#### END CPUS FACTS ####"

echo "#### BEGIN MEM FACTS ####"
free
echo "#### END CPUS FACTS ####"

echo "#### BEGIN SYSCTL FACTS ####"
sysctl -a
echo "#### END SYSCTL FACTS ####"
} 2>/dev/null | display_system_facts_${details}
