#!/bin/bash
# Run on the Mac: runs "$@" inside Terminal.app (which holds the Accessibility grant) and waits.
# Output lands in /tmp/e2e/out, exit code is propagated. Terminal is the only app we grant Accessibility to.
set -u
d=/tmp/e2e; mkdir -p $d; rm -f $d/out $d/done
printf '#!/bin/bash\ncd %q\n%s > %s/out 2>&1\necho $? > %s/done\n' "$PWD" "$(printf '%q ' "$@")" $d $d > $d/run.sh
chmod +x $d/run.sh
open -a Terminal $d/run.sh
until [ -f $d/done ]; do sleep 1; done
cat $d/out
exit "$(cat $d/done)"
