#! /bin/sh

[ "$DEBUG" = "true" ] || DEBUG=false

debug() {
    $DEBUG && echo "[DEBUG] $@" >&2
}

init_infos() {
    if [ -z "$APT_VERSIONS" ] ; then
	which apt-show-versions 1>/dev/null 2>/dev/null &&
	APT_VERSIONS=`apt-show-versions` || APT_VERSIONS=
    fi
    debug "APT_VERSIONS=$APT_VERSIONS"
}

# nbs-munin-node/unknown upgradeable from 0.8 to 0.9.2
# nbs-nagios-nrpe/unknown uptodate 0.9.4
get_apt_versions_full() {
    awk '
function join_yaml(array, start, end, sep) {
  result = array[start]
  for (i = start + 1; i <= end; i++)
    result = result sep array[i]
  return result
}
{
  if ( $2 ~ /upgradeable/ ) {
    gsub("/", " ");
    split($0, fields, " ");
    gsub(":", "_", fields[5])
    gsub(":", "_", fields[7])
    lines[NR] = sprintf("%s: {dist: %s, status: %s, version: \"%s\", upgrade: \"%s\"}",
                        fields[1], fields[2], fields[3], fields[5], fields[7]);

  } else {
    gsub("/"," ");
    split($0, fields, " ");
    gsub(":", "", fields[2])
    gsub(":", "", fields[3])
    gsub(":", "_", fields[4])
    lines[NR] = sprintf("%s: {dist: %s, status: %s, version: \"%s\"}",
                        fields[1], fields[2], fields[3],
                        join_yaml(fields, 4, NF, " "));
  }
}
END {
  printf("apt_versions: {%s}\n", join_yaml(lines, 1, NR, ", "))
}
'
}
get_apt_versions_light() {
    awk '{
           if ( $2 ~ /upgradeable/ ) { upgradeable++ }
           else { uptodate++ }
         } END {
             printf("apt_uptodate: %d\n", uptodate)
             printf("apt_upgradeable: %d\n", upgradeable)
         }'
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

init_infos

[ -z "$APT_VERSIONS" ] ||
echo "$APT_VERSIONS" | get_apt_versions_${details}
