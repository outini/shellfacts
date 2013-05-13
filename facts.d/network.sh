#!/bin/sh

[ "$DEBUG" = "true" ] || DEBUG=false

PATH=$PATH:/sbin:/usr/sbin

init_infos() {
    [ "`whoami`" = "root" ] ||
    echo "superuser is required, informations may not be accurate" >&2

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
    awk -v "OS=$OS" '
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
    echo "${BRCFG}" |
    awk -v OS="$OS" '
BEGIN {
    bridges_count = 0
    print "network_bridges:"
    print "  bridges:"
}

/^[a-z0-9]/ {
    # ignore the Linux brctl header
    if (OS == "Linux" && NR == 1) next

    bridges_count++
    gsub(/:$/, "", $1)
    print "  - name: \"" $1 "\""

    if (OS == "Linux") {
        print "    id: \"" $2 "\""
        print "    stp: \"" $3 "\""
        print "    interfaces:"
        print "    - \"" $4 "\""
    }
}

{
    if (OS == "Linux" && NF == 1)
        print "    - \"" $1 "\""

    if (config_section == 1 && $1 != "Interfaces:")
        for (i = 1; i <= NF; i++) print "      " $(i++) ": \"" $i "\""

    if (interface_section == 1 && $2 ~ /flags=/) print "    - \"" $1 "\""

    # assume "Address cache" is the last section
    if ($0 ~ /^\s+Address cache/) interface_section = 0

    if ($1 == "Configuration:") {
        config_section = 1
        print "    configuration:"
    }
    # assume that "interfaces" are below "configuration"
    if ($1 == "Interfaces:") {
        config_section = 0
        interface_section = 1
        print "    interfaces:"
    }
}

END {
    print "  bridges_count: " bridges_count
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
	verify) init_infos ; exit ;;
        *) echo "unknown arg: $1"; shift ;;
    esac
done

init_infos 2>/dev/null
get_ifs_facts
get_bridges_facts
get_routes_facts
get_resolver_facts
