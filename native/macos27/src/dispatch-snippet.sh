# BATTERY_MACOS27_NATIVE_DISPATCH_BEGIN
# Opt-in backend only: leave the existing CLI unchanged on all other installs.
if [[ -f /Library/PrivilegedHelperTools/co.palokaj.battery.macos27/active && \
      -x /Library/PrivilegedHelperTools/co.palokaj.battery.macos27/native-charge ]]; then
    exec /bin/bash /Library/PrivilegedHelperTools/co.palokaj.battery.macos27/battery-native.sh "$@"
fi
# BATTERY_MACOS27_NATIVE_DISPATCH_END
