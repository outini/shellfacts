#!/bin/sh

[ "$DEBUG" = "true" ] || DEBUG=false

PATH=$PATH:/sbin:/usr/sbin

init_infos() {
    OS=`uname -s`
    case $OS in
	Linux)
	    IFCFG=`ip addr show`
	    BRCFG=`brctl show`
	    NETSTAT=`netstat -rn -46`
	    ;;
	*)
	    IFCFG=`ifconfig -a`
	    BRCFG=`brconfig -a`
	    NETSTAT=`netstat -rn -finet ; netstat -rn -finet6`
	    ;;
    esac
    RESOLVCFG="/etc/resolv.conf"
}

get_ifs_facts_light()
{ :; }
get_ifs_facts_full()
{
    [ -z "${IFCFG}" ] ||
    echo "${IFCFG}" |awk -v os="$OS" '
        BEGIN {
	    start = "interface_%d: { "
	    hasip4 = 0
	    hasip6 = 0
	    num = 0
	}

	/^[a-z0-9]+:/ {
	    # close brackets from ip6 or ip4
	    if (hasip6 == 1 || (hasip6 == 0 && hasip4 == 1)) printf(" ]")
	    printf(start, num)
	    # new interface
	    hasip4 = 0
	    hasip6 = 0
	    num++
	    start = " }\ninterface_%d: { "
	    if (os = "Linux")
		 interface = $2
	    else
		 interface = $1
	    sub(/:/, "", interface)
	    if (interface ~ "@") {
		 split(interface, vlan, "@")
		 split(vlan[1], ifvlan, ".")
		 printf("name: %s, vlan: %s, parent: %s",
                       vlan[1], ifvlan[2], vlan[2])
	    } else
		 printf("name: %s", interface)
	}

	/inet.?\ / {
	    ip = $2
	    sub(/\/[0-9]+/, "", ip)
	    if (ip !~ ":")
	    if (hasip4 == 0) {
	        printf(", ipv4_addr: [ \"%s\"", ip)
	        hasip4 = 1
	    } else
	       printf(", \"%s\"", ip)
	  else {
		      if (hasip6 == 0) {
		          # assume ipv6 address always come after ipv4
			  if (hasip4 == 1) printf(" ]")
			  printf(", ipv6_addr: [ \"%s\"", ip)
			  hasip6 = 1
		      } else
			  printf(", \"%s\"", ip)
		  }
	     }

	     /(link\/ether|address:)/ {
	         printf(", mac_addr: \"%s\"", $2)
	     }

	     END {
	         if (hasip6 == 1 || (hasip6 == 0 && hasip4 == 1))
		     printf(" ]")
		 print " }"
	     }
	'
}

get_bridges_facts_light()
{
    [ -z "${BRCFG}" ] ||
    echo "${BRCFG}" | awk '
        /^[a-z0-9]/ && NR > 1 { count++ }
        END { print "network_bridges_count: " count }
        '
}
get_bridges_facts_full()
{
    [ -z "${BRCFG}" ] ||
    echo "${BRCFG}" | awk '
        function join(array, start, end, sep) {
            result = array[start]
            for (i = start + 1; i <= end; i++)
              result = result sep array[i]
            return result
        }

	/^[a-z0-9]/ && NR > 1 {
            if (j > 0) {
                members = mbrs[0]
                for (x = 1; x < j; x++) members = members ", " mbrs[x]
                brs[i-1] = brs[i-1] " [" members "]}"
            }
            j = 0
	    brs[i++] = sprintf("{name: %s, stp_ena: %s, members:", $1, $3)
            mbrs[j++] = $4
	}
	{ if (NF == 1) mbrs[j++] = $1 }

	END {
            if (j > 0) {
                members = mbrs[0]
                for (x = 1; x < j; x++) members = members ", " mbrs[x]
                brs[i-1] = brs[i-1] " [" members "]}"
            }
            printf("network_bridges: [%s]\n", join(brs, 0, length(brs), ", "))
	}
	'
}

get_routes_facts()
{
    ## Linux ipv4 / ipv6
    # Destination / Gateway / Genmask / Flags / MSS / Window / irtt / Iface
    # Destination / Next Hop / Flag / Met / Ref / Use / If
    ## Unix ipv4 == ipv6
    # Destination / Gateway / Flags / Refs / Use / Mtu / Interface

    echo "$NETSTAT" |
    awk -v "OS=$OS" '
BEGIN {
    print "network_routing:"
    print "  routes:"
}

! /(^[A-Za-z]+[\ \t]|^default)/ {
    dest = $1
    gw = $2

    if ($1 == "0.0.0.0") dest = "default"
    if ($2 == "0.0.0.0" || $2 ~ "::1?") gw = "local"

    if (dest !~ ":") {
netmask = $3
interface = $8
type = "ipv4"
    } else {
split(dest, dest_ip6, "/")
dest = dest_ip6[1]
netmask = "/" dest_ip6[2]
interface = $7
type = "ipv6"
    }

    printf("  - destination: \"%s\"\n", dest)
    printf("    gateway: \"%s\"\n", gw)
    printf("    netmask: \"%s\"\n", netmask)
    printf("    interface: \"%s\"\n", interface)

    if (type == "ipv6") ipv6_routes_count++
    else ipv4_routes_count++
    total_routes_count++
}

END {
    print "  routes_ipv4_count: " ipv4_routes_count
    print "  routes_ipv6_count: " ipv6_routes_count
    print "  routes_total_count: " total_routes_count
}
'
}

get_resolver_facts()
{
    details_level="$1"

    awk	'
BEGIN {
    resolver = ""
    domain = ""
    ysearch = ""

    print "network_resolver:"
}

/nameserver/ { print "  ip: " $2 }
/domain/ { print "  domain: " $2 }
/search/ {
    print "  search:"
    for (i = 2; i <= NF; i++) print "  - " $i
}
' "$RESOLVCFG"
}


while [ $# -gt 0 ]; do
    case "$1" in
        *) echo "unknown arg: $1"; shift ;;
    esac
done

init_infos 2>/dev/null
#get_ifs_facts_$details
#get_bridges_facts_$details
get_routes_facts
get_resolver_facts
