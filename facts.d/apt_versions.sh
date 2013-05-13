#! /bin/sh

[ "$DEBUG" = "true" ] || DEBUG=false

debug() {
    $DEBUG && echo "[DEBUG] $@" >&2
}

init_infos() {
    APT_VERSIONS=`apt-show-versions`
}

get_apt_versions() {
    [ -z "$APT_VERSIONS" ] ||
    echo "$APT_VERSIONS" | awk '
BEGIN {
    print "apt_versions:"
    print "  packages:"
}

{
    if ( $2 ~ /upgradeable/ ) {
        gsub("/", " ");
        split($0, fields, " ");
        #gsub(":", "_", fields[5])
        #gsub(":", "_", fields[7])

        print "  - name: \"" fields[1] "\""
        print "    dist: \"" fields[2] "\""
        print "    status: \"" fields[3] "\""
        print "    version: \"" fields[5] "\""
        print "    upgrade: \"" fields[7] "\""

        upgradeable++

    } else {
        gsub("/"," ");
        len_fields = split($0, fields, " ");
        #gsub(":", "", fields[2])
        gsub(":", "", fields[3])
        #gsub(":", "_", fields[4])

        print "  - name: \"" fields[1] "\""
        print "    dist: \"" fields[2] "\""
        print "    status: \"" fields[3] "\""

        version=fields[4]
        for (i = 5; i <= len_fields; i++)
            version = sprintf("%s %s", version, fields[i])
        print "    version: \"" version "\""

        uptodate++

    }
}

END {
    print "  uptodate_packages: " uptodate
    print "  upgradeable_packages: " upgradeable
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
        *) echo "unknown arg: $1"; shift ;;
    esac
done

init_infos 2>/dev/null
get_apt_versions
