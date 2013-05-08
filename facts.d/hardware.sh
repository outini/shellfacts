#! /bin/sh

[ "$DEBUG" = "true" ] || DEBUG=false

die() {
    echo "$@" >&2
    exit 2
}
init_infos() {
    [ -z "$DMIDECODE" ] && { DMIDECODE=`dmidecode` || DMIDECODE= ; }
    [ -z "$LSPCI" ] && { LSPCI=`lspci` || LSPCI= ; }
}
dmidecode_parse() {
    block_name="$1"
    [ -z "$2" ] && body_actions="print" || body_actions="$2"
    [ -z "$3" ] && end_actions= || end_actions="$3"

    [ -z "$DMIDECODE" ] ||
    echo "$DMIDECODE" | awk "/^$block_name/,/^$/{
           $body_actions
         } END { $end_actions }"
}
get_pci_facts_light() {
    [ -z "$LSPCI" ] ||
    echo "$LSPCI" | awk -F: '
        /Ethernet controller/ { gsub("^[[:space:]]+", "", $3); eth = $3 }
        /storage controller/ { gsub("^[[:space:]]+", "", $3); disk = $3 }
        END {
            printf("ethernet_controller: %s\n", eth)
            printf("storage_controller: %s\n", disk)
        }'
}
get_pci_facts_full() {
    [ -z "$LSPCI" ] ||
    echo "$LSPCI" | awk -F: '
        /Ethernet controller/ {
            gsub("^[[:space:]]+", "", $3)
            ethernet[i++] = sprintf("controller_%d: %s", i, $3) }
        /storage controller/ {
            gsub("^[[:space:]]+", "", $3)
            storage[j++] = sprintf("controller_%d: %s", j, $3) }

        END {
            pci_eths = ethernet[0]
            for (x = 1; x < i; x++) pci_eths = pci_eths ", " ethernet[x]

            pci_stores = storage[0]
            for (y = 1; y < j; y++) pci_stores = pci_stores ", " storage[y]

            printf("pci_infos: {ethernet_controllers: {%s}, ", pci_eths)
            printf("storage_controllers: {%s}}\n", pci_stores)
        }'
}

get_dmi_facts_light() {
    # dmidecode only display 2 lines of comment
    # if it has not access to chassis informations (ie. virtual machine)
    [ `echo -n "$DMIDECODE" | wc -l` -gt 2 ] || {
        echo "product_model: virtual machine" && return 0
    }
    ## Get product informations
    awk_body='
        if (/^[[:space:]]+Product Name:/) {
            gsub(".*:[[:space:]]+", "product_model: "); print $0 }
        if (/^[[:space:]]+Serial Number:/) {
            gsub(".*:[[:space:]]+", "product_serial: "); print $0 }'
    dmidecode_parse 'System Information' "$awk_body"

    ## Get enclosure informations
    awk_body='
         if (/^[[:space:]]+Serial Number: .[^.]+..[^.]+./) {
             split($0,infos,".")
             if (!length(infos[3])) {
                 printf("enclosure_serial: %s\n", infos[2]) }}
         if (/^[[:space:]]+Enclosure Serial:/) {
           gsub(".*:[[:space:]]+", "enclosure_serial: "); printf("%s\n", $0) }'
    dmidecode_parse '(HP ProLiant System\/Rack Locator|Base Board)' "$awk_body"

    ## Get processors informations
    awk_body='
         if (/[[:space:]]*Version:/) {
             gsub(".*:[[:space:]]+",""); gsub("[[:space:]]+$","")
             if (!/Not Spec/) { cpu_model = sprintf("%s", $0); used_cpu++ }
         }
         if (/Core Count:/) { gsub(".*:[[:space:]]+",""); core_count += $0 }'
    awk_end='
         printf("hw_cpu_count: %d\n", used_cpu)
         printf("hw_cpu_model: %s\n", cpu_model)
         printf("hw_core_count: %d\n", core_count)'
    dmidecode_parse 'Processor Information' "$awk_body" "$awk_end"

    ## Get physical memory configuration and availability
    awk_body='
        if (/^Memory Device/) { count++ }
        if (/No Module Installed/) { free++ }
        if (/^[[:space:]]+Size:.* MB/) {
            gsub(".*:[[:space:]]+", "")
            gsub("[[:space:]]+MB.*", "")
            size += $0
        }'
    awk_end='
        printf("hw_mem_free_slots: %d\n", free)
        printf("hw_mem_total_slots: %d\n", count)
        printf("hw_mem_size: %d\n", size)'
    dmidecode_parse 'Memory Device' "$awk_body" "$awk_end"
}
get_dmi_facts_full() {
    # dmidecode only display 2 lines of comment
    # if it has not access to chassis informations (ie. virtual machine)
    [ `echo "$DMIDECODE" | wc -l` -gt 2 ] || {
        echo "product_model: virtual machine" && return 0
    }

    ## Get product informations
    awk_body='if (/^[[:space:]]+Manufacturer:/) {
           gsub(".*:[[:space:]]+", "manufacturer: "); product = sprintf("%s",$0) }
         if (/^[[:space:]]+Product Name:/) {
           gsub(".*:[[:space:]]+", "model: "); product = sprintf("%s, %s",product,$0) }
         if (/^[[:space:]]+Serial Number: /) {
           gsub(".*:[[:space:]]+", "serial: "); product = sprintf("%s, %s",product,$0) }'
    awk_end='printf("product: {%s}\n",product)'
    dmidecode_parse 'System Information' "$awk_body" "$awk_end"

    ## Get enclosure informations
    awk_body='gsub("[[:space:]]+$","")
         if (/^[[:space:]]+Serial Number: .[^.]+..[^.]+./) {
           split($0,infos,".")
           if (!length(infos[3])) {
             printf("enclosure: {serial: %s, bay: %s}\n",infos[2], infos[4]) }}
         if (/^[[:space:]]+Enclosure Name:/) {
           gsub(".*:[[:space:]]+", "name: "); enclosure = sprintf("enclosure: {%s",$0) }
         if (/^[[:space:]]+Enclosure Model:/) {
           gsub(".*:[[:space:]]+", "model: "); enclosure = sprintf("%s, %s",enclosure,$0) }
         if (/^[[:space:]]+Enclosure Serial:/) {
           gsub(".*:[[:space:]]+", "serial: "); enclosure = sprintf("%s, %s",enclosure,$0) }
         if (/^[[:space:]]+Server Bay:/) {
           gsub(".*:[[:space:]]+", "bay: "); printf("%s, %s}\n",enclosure,$0) }'
    dmidecode_parse '(HP ProLiant System\/Rack Locator|Base Board)' "$awk_body"

    ## Get processors informations
    awk_body='
         if (/[[:space:]]*Version:/) {
             total_cpu++
             gsub(".*:[[:space:]]+",""); gsub("[[:space:]]+$","")
             cpus[total_cpu] = sprintf("%s, model: %s", cpus[total_cpu], $0)
             if (/Not Spec/) { free_cpu++ }
             else { used_cpu++ }
         }
         if (/Max Speed:/) { gsub(".*:[[:space:]]+","")
             cpus[total_cpu] = sprintf("%s, speed: %s",cpus[total_cpu],$0)}
         if (/Core Count:/) { gsub(".*:[[:space:]]+","")
             cpus[total_cpu] = sprintf("%s, core_count: %s",cpus[total_cpu],$0)}
         if (/Core Enabled:/) { gsub(".*:[[:space:]]+","")
             cpus[total_cpu] = sprintf("%s, core_ena: %s",cpus[total_cpu],$0)}'
    awk_end='
         summary = sprintf("free: %d, used: %d, total: %d",
                       free_cpu, used_cpu, total_cpu)
         gsub("^,[[:space:]]*", "", cpus[1])
         slots = sprintf("slot_1: {%s}", cpus[1])
         for (n=2; n<=total_cpu; n++) {
             gsub("^,[[:space:]]*", "", cpus[n])
             slots = sprintf("%s, slot_%d: {%s}", slots, n, cpus[n])
         }
         printf("hw_cpu_infos: {summary: {%s}, slots: {%s}}\n",summary,slots)'

    dmidecode_parse 'Processor Information' "$awk_body" "$awk_end"

    ## Get physical memory configuration and availability
    awk_body='
        if (/^Memory Device/) { count++ }
        if (/No Module Installed/) { free++ }
        if (/^[[:space:]]+Size:/) {
            gsub(".*:[[:space:]]+", "size: ")
            mem[count] = sprintf("%s", $0)
        }
        if (/^[[:space:]]+Locator:/) {
            gsub(".*:[[:space:]]+", "locator: ")
            mem[count] = sprintf("%s, %s", mem[count], $0)
        }
        if (/^[[:space:]]+Type:/) {
            gsub(".*:[[:space:]]+", "type: ")
            mem[count] = sprintf("%s, %s", mem[count], $0)
        }'
    awk_end='
        summary = sprintf("free: %d, used: %d, total: %d", free, count-free, count)
        slots = sprintf("slot_1: {%s}", mem[1])
        for (n=2; n<=count; n++) {
            slots = sprintf("%s, slot_%d: {%s}", slots, n, mem[n])
        }
        printf("hw_mem_infos: {summary: {%s}, slots: {%s}}\n", summary, slots)'
    dmidecode_parse 'Memory Device' "$awk_body" "$awk_end"
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

init_infos 2>/dev/null
get_pci_facts_$details
get_dmi_facts_$details
