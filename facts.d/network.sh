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

get_ifs_facts()
{
    [ -z "${IFCFG}" ] ||
    echo "${IFCFG}" |
    awk -v OS="$OS" '
BEGIN {
    print "network_interfaces:"
}

/^[a-z0-9]+:/ {
    # new interface
    hasip4 = 0
    hasip6 = 0

    if (OS == "Linux") interface = $2
    else interface = $1
    sub(/:/, "", interface)

    if (interface ~ "@") {
        split(interface, vlan, "@")
        split(vlan[1], ifvlan, ".")
        printf("- name: %s\n", vlan[1])
        printf("  vlan: %s\n", ifvlan[1])
        printf("  parent: %s\n", vlan[2])
    } else
        printf("- name: %s\n", interface)
}

/inet.?\ / {
    if (OS == "Linux")
        split($2, cidr, "/")
    else
        if ($2 == "alias") {
            cidr[1] = $3
            cidr[2] = $5
        } else {
            cidr[1] = $2
            cidr[2] = $4
        }

    gsub(/%.*$/, "", cidr[1])

    if (cidr[1] !~ ":" && hasip4 == 0) {
        print "  ipv4_addr:"
        hasip4 = 1
    } else if (hasip6 == 0) {
        # assume ipv6 address always come after ipv4
        print "  ipv6_addr:"
        hasip6 = 1
    }
    printf("  - address: \"%s\"\n", cidr[1])
    printf("    netmask: \"%s\"\n", cidr[2])
}

/(link\/ether|address:)/ {
    printf("  mac_addr: \"%s\"\n", $2)
}
'
}

get_bridges_facts()
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

    [ -z "$NETSTAT" ] ||
    echo "$NETSTAT" |
    awk -v "OS=$OS" '
BEGIN {
    print "network_routing:"
    print "  routes:"
}

# ignore the header line
/(^Destination|Internet|Kernel)/ { next }

/(^[a-f0-9:]+|^default)/ {
    dest = $1
    gw = $2

    if (OS == "Linux" && dest !~ ":") {
        netmask = $3
        interface = $8
        type = "ipv4"
    } else {
        split(dest, dest_ip6, "/")
        dest = dest_ip6[1]
        netmask = dest_ip6[2]
        interface = $7
        if (dest ~ ":") type = "ipv6"
        else type = "ipv4"
    }

    gsub(/%.*$/, "", dest)

    printf("  - destination: \"%s\"\n", dest)
    printf("    gateway: \"%s\"\n", gw)
    printf("    netmask: \"%s\"\n", netmask)
    printf("    interface: \"%s\"\n", interface)
    printf("    type: \"%s\"\n", type)

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
/nameserver/ { nameservers[n++] = $2 }
/domain/ { domain = $2 }
/search/ { for (i = 2; i <= NF; i++) search[s++] = $i }

END {
    print "network_resolver:"
    print "  domain: " domain
    print "  nameservers:"
    for (i in nameservers) print "  - " nameservers[i]
    print "  search:"
    for (i in search) print "  - " search[i]
}
' "$RESOLVCFG"
}


while [ $# -gt 0 ]; do
    case "$1" in
        *) echo "unknown arg: $1"; shift ;;
    esac
done

init_infos 2>/dev/null
get_ifs_facts
#get_bridges_facts
get_routes_facts
get_resolver_facts
