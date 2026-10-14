#!/bin/bash
# Local checkout compatibility entry point. The official curl installer would
# install the upstream build, which does not contain this firmware controller.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[[ -f "$source_dir/install-local.sh" ]] || {
    echo 'Use a local checkout and run ./install-local.sh; this build has no remote installer.' >&2
    exit 1
}
exec /bin/bash "$source_dir/install-local.sh" "$@"
