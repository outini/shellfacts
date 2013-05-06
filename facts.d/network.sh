#!/bin/sh

[ "$DEBUG" = "true" ] || DEBUG=false

PATH=$PATH:/sbin:/usr/sbin

init_infos() {
    OS=`uname -s`
    case $OS in
	Linux)
	    [ -z "$IFCFG" ] &&
	    { IFCFG=`ip addr show` || IFCFG= ; }
	    [ -z "$BRCFG" ] &&
	    { BRCFG=`brctl show` || BRCFG= ; }
	    ;;
	*)
	    [ -z "$IFCFG" ] &&
	    { IFCFG=`ifconfig -a` || IFCFG= ; }
	    [ -z "$BRCFG" ] &&
	    { BRCFG=`brconfig -a` || BRCFG= ; }
	    ;;
    esac
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
            bridges = brs[0]
            for (x = 1; x < i; x++) bridges = bridges ", " brs[x]
            printf("network_bridges: [%s]\n", bridges)
	}
	'
}

get_routes_facts_light()
{
    netstat -rn -46 | awk '
        ! /^[A-Z\ \t]/ {
            if ($1 == "0.0.0.0") { printf("network_ipv4_gw: \"%s:%s\"\n", $2, $8) }
        }'
}
get_routes_facts_full()
{
    netstat -rn -46 | awk '
	BEGIN {num = 0}
	! /^[A-Z\ \t]/ {
	    dest = $1
	    gw = $2
	    if ($1 == "0.0.0.0") dest = "default"
	    if ($2 == "0.0.0.0" || $2 ~ "::1?") gw = "local"
	    printf("route_%d: { destination: \"%s\", gateway: \"%s\"", num, dest, gw)
	    if (dest !~ ":")
	        printf(", netmask: %s, interface: %s }\n", $3, $8)
	    else
	        printf(", interface: %s }\n", $7)
		num++
	    }
	'
}

get_resolver_facts_light()
{
    awk '
        /nameserver/ { printf("resolver_ip: \"%s\"\n", $2) }
        /domain/ { printf("resolver_domain: \"%s\"\n", $2) }
        ' /etc/resolv.conf
}
get_resolver_facts_full()
{
    awk '
	/nameserver/ { resolver = $2 }
	/domain/ { domain = $2 }
	/search/ {
	    ysearch = $2
	    for (i = 3; i <= NF; i++) ysearch = ysearch ", " $i
	}
	END {
            printf("resolver: { ip: %s, domain: %s, search: [ %s ] }\n",
		    resolver, domain, ysearch)
        }' /etc/resolv.conf
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

init_infos 2>/dev/null
get_ifs_facts_$details
get_bridges_facts_$details
get_routes_facts_$details
get_resolver_facts_$details
