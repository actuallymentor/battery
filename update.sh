#!/bin/bash
# An upstream update must not silently remove local firmware support.
printf '%s\n' 'Update the local checkout, review it, then run ./install-local.sh.' >&2
exit 1
