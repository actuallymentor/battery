/* SPDX-License-Identifier: MIT
 * Local, experimental compatibility backend for actuallymentor/battery 1.3.4.
 * Fixed-ceiling draft 0.1.4. Not an upstream release. Runtime capability probe.
 * Independent restart thresholds and forced discharge are NOT emulated.
 *
 * Native preference mechanism documented in az-code-lab/ampere v0.0.65,
 * Sources/Shared/NativeChargeLimit.swift and Sources/SMCWriter/main.swift.
 * See THIRD-PARTY-NOTICES.md. This is a separate implementation, not Ampere.
 */
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <notify.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <signal.h>
#include <libproc.h>
#include <sys/sysctl.h>
#include "policy.h"
#include "native-policy.h"

static NSString *const StateDir = @"/private/var/db/co.palokaj.battery.macos27";
static NSString *const StateFile = @"/private/var/db/co.palokaj.battery.macos27/state.plist";
static CFStringRef const Domain = CFSTR("com.apple.smartcharging.topoffprotection");
static CFStringRef const FeatureKey = CFSTR("MCLFeatureState");
static CFStringRef const LimitKey = CFSTR("mclLimitValue");
static const char *ReloadNotification = "com.apple.smartcharging.defaultschanged";
static NSString *failure = nil;
static BOOL removeOwnedPolicy(NSMutableDictionary *state);
static BOOL daemonMode = NO;
static volatile sig_atomic_t daemonWake, daemonStop;

/* Declarations only: these selectors are dynamically provided by PowerUI.
 * Every selector is checked before use. No Apple private headers are shipped.
 */
@interface NSObject (B27PowerUI)
- (id)initWithClientName:(NSString *)name;
- (BOOL)isMCLSupported;
- (uint64_t)isMCLCurrentlyEnabled:(NSError **)error;
- (BOOL)enableMCL:(NSError **)error;
- (BOOL)disableMCL:(NSError **)error;
- (BOOL)setMCLLimit:(uint8_t)target error:(NSError **)error;
@end

static BOOL fail(NSString *message) { failure = message; return NO; }
static double now(void) { return NSDate.date.timeIntervalSince1970; }
static void note(NSString *text) {
    fprintf(stderr, "%s %s\n", NSDate.date.description.UTF8String, text.UTF8String);
}

static id powerClient(void) {
    static void *framework = NULL;
    if (!framework) framework = dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI", RTLD_NOW);
    if (!framework) {
        fail(@"PowerUI framework is unavailable. No charging settings changed."); return nil;
    }
    Class cls = NSClassFromString(@"PowerUISmartChargeClient");
    if (!cls || ![cls instancesRespondToSelector:@selector(initWithClientName:)]) {
        fail(@"PowerUI client API is unavailable or changed."); return nil;
    }
    id client = [[cls alloc] initWithClientName:@"battery-macos27-local"];
    for (NSString *name in @[@"isMCLSupported", @"isMCLCurrentlyEnabled:", @"enableMCL:", @"disableMCL:"]) {
        if (![client respondsToSelector:NSSelectorFromString(name)]) {
            fail([@"PowerUI selector missing: " stringByAppendingString:name]); return nil;
        }
    }
    if (![client isMCLSupported]) { fail(@"Native charge limiting is not supported on this Mac."); return nil; }
    return client;
}

/* This function checks path components without following user-made symlinks. */
static BOOL protectedDirectory(NSString *path) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode) ||
        st.st_uid != 0 || (st.st_mode & 0022) != 0)
        return fail([@"Unsafe or missing root-owned directory: " stringByAppendingString:path]);
    return YES;
}

static int stateLock(void) {
    for (NSString *p in @[@"/private", @"/private/var", @"/private/var/db"]) {
        if (!protectedDirectory(p)) return -1;
    }
    if (mkdir(StateDir.fileSystemRepresentation, 0700) != 0 && errno != EEXIST) {
        fail(@"Cannot create state directory."); return -1;
    }
    if (!protectedDirectory(StateDir)) return -1;
    NSString *lockPath = [StateDir stringByAppendingPathComponent:@"lock"];
    int fd = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW, 0600);
    struct stat st;
    if (fd < 0 || fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != 0 ||
        (st.st_mode & 0077) != 0 || st.st_nlink != 1) {
        if (fd >= 0) close(fd);
        fail(@"Unsafe state lock file."); return -1;
    }
    /* A stuck private-API call must not leave all subsequent CLI calls blocked. */
    for (int i = 0; i < 100; ++i) {
        if (flock(fd, LOCK_EX | LOCK_NB) == 0) return fd;
        if (errno != EWOULDBLOCK && errno != EAGAIN) break;
        usleep(100000);
    }
    close(fd); fail(@"Backend is busy. Inspect launchd and retry; settings were not changed by this call."); return -1;
}

static NSMutableDictionary *readState(void) {
    struct stat st;
    if (lstat(StateFile.fileSystemRepresentation, &st) != 0) {
        if (errno == ENOENT) return [@{@"schema": @1, @"enabled": @NO,
                                     @"lower": @80, @"upper": @80,
                                     @"chargingPhase": @NO, @"holdTarget": @0} mutableCopy];
        fail(@"Cannot read backend state."); return nil;
    }
    if (!S_ISREG(st.st_mode) || st.st_uid != 0 || (st.st_mode & 0077) || st.st_size > 65536) {
        fail(@"Unsafe or oversized state file."); return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:StateFile];
    NSError *error = nil;
    id value = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers
                                                                    format:NULL error:&error] : nil;
    if (![value isKindOfClass:NSMutableDictionary.class] || ![value[@"schema"] isEqual:@1]) {
        fail(@"Invalid backend state; refusing to replace the recovery snapshot."); return nil;
    }
    for (NSString *key in @[@"lower", @"upper", @"enabled", @"chargingPhase", @"holdTarget"]) {
        if (![value[key] isKindOfClass:NSNumber.class]) { fail(@"Malformed backend state."); return nil; }
    }
    if (!b27_valid_saved_range([value[@"lower"] intValue], [value[@"upper"] intValue])) {
        fail(@"Invalid saved threshold range."); return nil;
    }
    return value;
}

static BOOL saveState(NSDictionary *state) {
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:state format:NSPropertyListXMLFormat_v1_0
                                                           options:0 error:&error];
    if (!data || ![data writeToFile:StateFile options:NSDataWritingAtomic error:&error])
        return fail([NSString stringWithFormat:@"Cannot save recovery state: %@", error.localizedDescription ?: @"unknown"]);
    if (chmod(StateFile.fileSystemRepresentation, 0600) != 0) return fail(@"Cannot protect state file.");
    return YES;
}

static NSNumber *preference(CFStringRef key) {
    id value = CFBridgingRelease(CFPreferencesCopyValue(key, Domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}
static BOOL flushPreferences(void) {
    if (!CFPreferencesSynchronize(Domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
        return fail(@"Native charging preferences could not be synchronized.");
    if (notify_post(ReloadNotification) != NOTIFY_STATUS_OK)
        return fail(@"Could not notify PowerUIAgent to reload the charge limit.");
    return YES;
}
static void setPreference(CFStringRef key, NSNumber *value) {
    CFPreferencesSetValue(key, (__bridge CFPropertyListRef)value, Domain,
                          kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

static BOOL captureOriginal(NSMutableDictionary *state) {
    if ([state[@"hasOriginal"] boolValue]) return YES;
    if (!CFPreferencesSynchronize(Domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
        return fail(@"Cannot read native preference domain.");
    NSNumber *feature = preference(FeatureKey), *limit = preference(LimitKey);
    if (feature && feature.intValue != 0 && feature.intValue != 1)
        return fail(@"Unrecognized native charge-limit feature state. Refusing to overwrite it.");
    if (feature.intValue == 1 && (!limit || limit.intValue < 1 || limit.intValue > 100))
        return fail(@"The existing native limit is inconsistent; inspect System Settings first.");
    state[@"hasOriginal"] = @YES;
    if (feature) state[@"originalFeature"] = feature;
    if (limit) state[@"originalLimit"] = limit;
    state[@"savedAt"] = @(now());
    return saveState(state); /* journal BEFORE changing Apple preferences */
}

static BOOL disableViaAgent(void) {
    id client = powerClient();
    if (!client) return NO;
    NSError *error = nil;
    uint64_t enabled = [client isMCLCurrentlyEnabled:&error];
    if (error) return fail([@"Could not query native charge control: " stringByAppendingString:error.localizedDescription]);
    if (!enabled) {
        error = nil;
        if (![client enableMCL:&error] || error)
            return fail([NSString stringWithFormat:@"Cannot prepare native limit release: %@", error.localizedDescription ?: @"request rejected"]);
    }
    error = nil;
    if (![client disableMCL:&error] || error)
        return fail([NSString stringWithFormat:@"Native limit release failed: %@", error.localizedDescription ?: @"request rejected"]);
    return YES;
}

static BOOL writeTarget(int target) {
    if (target < 1 || target > 100) return fail(@"Invalid native target.");
    if (target == 100) {
        /* A preference write to feature=0 alone can leave powerd's registration
         * behind. Use the agent's disable API, as documented by Ampere. */
        if (!disableViaAgent()) return NO;
        setPreference(LimitKey, @100);
        return flushPreferences();
    }
    /* A defaults notification alone can leave PowerUI in ChargingToFull after
     * disableMCL. Explicitly re-engage its controller before applying the
     * requested (possibly below-80%) preference. This path is only used when
     * the target changes or registration needs repair, never every tick. */
    id client = powerClient();
    if (!client) return NO;
    NSError *error = nil;
    BOOL enabled = target >= 80 && [client respondsToSelector:@selector(setMCLLimit:error:)] ?
        [client setMCLLimit:(uint8_t)target error:&error] : [client enableMCL:&error];
    if (!enabled || error)
        return fail([NSString stringWithFormat:@"Cannot enable native charge control: %@",
                     error.localizedDescription ?: @"request rejected"]);
    setPreference(FeatureKey, @1);
    setPreference(LimitKey, @(target));
    if (!flushPreferences()) return NO;
    if (preference(FeatureKey).intValue != 1 || preference(LimitKey).intValue != target)
        return fail(@"Native preferences did not retain the requested target.");
    return YES;
}

static BOOL restoreOriginal(NSMutableDictionary *state) {
    state[@"enabled"] = @NO;
    if (![state[@"hasOriginal"] boolValue]) return saveState(state);
    state[@"restorePending"] = @YES;
    NSNumber *feature = state[@"originalFeature"], *limit = state[@"originalLimit"];
    if ((feature && ![feature isKindOfClass:NSNumber.class]) || (limit && ![limit isKindOfClass:NSNumber.class]))
        return fail(@"Invalid recovery snapshot; refusing to guess the original settings.");
    if (!saveState(state) || !removeOwnedPolicy(state) || !disableViaAgent()) return NO;
    /* Restoring an enabled original limit must also re-engage the controller;
     * a preference-only restore can leave it in ChargingToFull. */
    if (feature.intValue == 1 && !writeTarget(limit.intValue)) return NO;
    setPreference(FeatureKey, feature);
    setPreference(LimitKey, limit);
    if (!flushPreferences()) return NO;
    if ((feature && ![preference(FeatureKey) isEqual:feature]) ||
        (!feature && preference(FeatureKey)) ||
        (limit && ![preference(LimitKey) isEqual:limit]) || (!limit && preference(LimitKey)))
        return fail(@"Original native preferences could not be verified after restoration.");
    for (NSString *key in @[@"originalFeature", @"originalLimit", @"hasOriginal", @"restorePending",
                            @"lastRequested", @"requestedAt", @"pendingSince", @"lastError", @"manual",
                            @"enforcementWarning"]) {
        [state removeObjectForKey:key];
    }
    note(@"Restored the original native charge-limit preferences via PowerUIAgent.");
    return saveState(state);
}

typedef struct {
    int percentage, minutes;
    BOOL charging, chargingKnown, external, externalKnown;
    BOOL currentKnown, instantKnown;
    int64_t currentMA, instantMA;
    BOOL fullChargeOverrideKnown, fullChargeOverride;
} BatteryInfo;

/* Read-only powerd notification state, observed on macOS 27.0 (26A428).
 * Unknown future values remain unknown. Never post or change this system
 * notification: it belongs to the system's charge-to-full policy. */
static void readFullChargeOverride(BatteryInfo *out) {
    int token = 0;
    uint64_t value = 0;
    if (notify_register_check("com.apple.system.powersources.chargingtofulloverride", &token) != NOTIFY_STATUS_OK)
        return;
    uint32_t result = notify_get_state(token, &value);
    notify_cancel(token);
    if (result == NOTIFY_STATUS_OK && value <= 1) {
        out->fullChargeOverrideKnown = YES;
        out->fullChargeOverride = value == 1;
    }
}

static NSString *enforcementWarning(BatteryInfo b, int target) {
    switch (b27_charge_warning(target, b.percentage, b.externalKnown && b.external,
                              b.chargingKnown && b.charging, b.currentKnown, b.currentMA,
                              b.instantKnown, b.instantMA,
                              b.fullChargeOverrideKnown && b.fullChargeOverride)) {
        case B27_CHARGE_WARNING_FULL_CHARGE_OVERRIDE:
            return @"macOS charge-to-full override is active. Verify the native no-charge-to-full flag and actual battery current; a saved ceiling alone is insufficient. Run battery diagnose for system evidence.";
        case B27_CHARGE_WARNING_ABOVE_CEILING:
            return @"Battery is charging at or above the requested ceiling. A registered limit does not prove enforcement. Run battery diagnose.";
        case B27_CHARGE_WARNING_NONE:
            return nil;
    }
}

/* Read only; never opens an SMC user client or writes registry properties. */
static void readRegistryTelemetry(BatteryInfo *out) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault,
                                                 IOServiceMatching("AppleSmartBattery"));
    if (!svc) return;
    CFMutableDictionaryRef properties = NULL;
    kern_return_t rc = IORegistryEntryCreateCFProperties(svc, &properties,
                                                        kCFAllocatorDefault, 0);
    IOObjectRelease(svc);
    if (rc != KERN_SUCCESS || !properties) return;
    NSDictionary *d = CFBridgingRelease(properties);
    NSNumber *external = d[@"ExternalConnected"];
    if ([external isKindOfClass:NSNumber.class]) {
        out->externalKnown = YES; out->external = external.boolValue;
    }
    NSNumber *current = d[@"Amperage"], *instant = d[@"InstantAmperage"];
    if ([current isKindOfClass:NSNumber.class])
        out->currentKnown = b27_decode_current(current.unsignedLongLongValue, &out->currentMA);
    if ([instant isKindOfClass:NSNumber.class])
        out->instantKnown = b27_decode_current(instant.unsignedLongLongValue, &out->instantMA);
}
static BOOL batteryInfo(BatteryInfo *out) {
    *out = (BatteryInfo){.minutes = -1};
    CFTypeRef snapshot = IOPSCopyPowerSourcesInfo();
    if (!snapshot) return fail(@"Battery data is unavailable.");
    CFArrayRef list = IOPSCopyPowerSourcesList(snapshot);
    BOOL found = NO;
    for (CFIndex i = 0; list && i < CFArrayGetCount(list); ++i) {
        CFDictionaryRef raw = IOPSGetPowerSourceDescription(snapshot, CFArrayGetValueAtIndex(list, i));
        NSDictionary *d = (__bridge NSDictionary *)raw;
        if (![d[@kIOPSTypeKey] isEqualToString:@kIOPSInternalBatteryType]) continue;
        NSNumber *current = d[@kIOPSCurrentCapacityKey], *maximum = d[@kIOPSMaxCapacityKey];
        if (![current isKindOfClass:NSNumber.class] || ![maximum isKindOfClass:NSNumber.class] ||
            maximum.longLongValue <= 0 || maximum.longLongValue > 1000000000LL ||
            current.longLongValue < 0 || current.longLongValue > maximum.longLongValue) continue;
        out->percentage = (int)(100LL * current.longLongValue / maximum.longLongValue);
        NSNumber *charging = d[@kIOPSIsChargingKey];
        out->chargingKnown = [charging isKindOfClass:NSNumber.class];
        out->charging = out->chargingKnown && charging.boolValue;
        NSNumber *minutes = d[out->charging ? @kIOPSTimeToFullChargeKey : @kIOPSTimeToEmptyKey];
        out->minutes = [minutes isKindOfClass:NSNumber.class] ? minutes.intValue : -1;
        NSString *source = d[@kIOPSPowerSourceStateKey];
        if ([source isEqualToString:@kIOPSACPowerValue] || [source isEqualToString:@kIOPSBatteryPowerValue]) {
            out->externalKnown = YES;
            out->external = [source isEqualToString:@kIOPSACPowerValue];
        }
        found = YES; break;
    }
    if (list) CFRelease(list);
    CFRelease(snapshot);
    if (!found) return fail(@"No valid internal battery percentage was found.");
    readRegistryTelemetry(out);
    readFullChargeOverride(out);
    return YES;
}

/* Read-back reports powerd registration, NOT a hardware charging measurement. */
static NSString *registeredOutput(void) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/pmset"];
    task.arguments = @[@"-g", @"battlimit"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) return nil;
    double deadline = now() + 5.0;
    while (task.running && now() < deadline) usleep(50000);
    if (task.running) {
        kill(task.processIdentifier, SIGKILL);
        [task waitUntilExit];
        return nil;
    }
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0 || data.length > 65536) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
static NSArray<NSNumber *> *registeredTargets(NSString *output) {
    if (!output) return nil;
    NSMutableArray *values = [NSMutableArray array];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"chargeSocLimitSoc\\s*=\\s*([0-9]+)" options:0 error:NULL];
    for (NSTextCheckingResult *m in [re matchesInString:output options:0 range:NSMakeRange(0, output.length)]) {
        [values addObject:@([[output substringWithRange:[m rangeAtIndex:1]] intValue])];
    }
    if (!values.count && [output rangeOfString:@"No battery level limits set" options:NSCaseInsensitiveSearch].location == NSNotFound)
        return nil; /* distinguish unrecognized output from no registered limits */
    return values;
}
static BOOL matchesTarget(NSArray<NSNumber *> *targets, int target) {
    if (!targets) return NO;
    if (target == 100) return targets.count == 0 ||
        [[NSSet setWithArray:targets] isEqualToSet:[NSSet setWithObject:@100]];
    if (!targets.count) return NO;
    for (NSNumber *n in targets) if (n.intValue != target) return NO;
    return YES;
}

static CFStringRef const PolicyDomain = CFSTR("com.apple.powerd.charging");
static NSString *bootSession(void) {
    char uuid[128] = {0}; size_t length = sizeof uuid;
    if (sysctlbyname("kern.bootsessionuuid", uuid, &length, NULL, 0) != 0 || length >= sizeof uuid)
        return nil;
    return [NSString stringWithUTF8String:uuid];
}
static NSDictionary *powerdPreferences(void) {
    if (!CFPreferencesSynchronize(PolicyDomain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost)) return nil;
    id prefs = CFBridgingRelease(CFPreferencesCopyMultiple(NULL, PolicyDomain,
        kCFPreferencesAnyUser, kCFPreferencesCurrentHost));
    return [prefs isKindOfClass:NSDictionary.class] ? prefs : nil;
}
static BOOL replacePolicyData(NSData *original, NSData *replacement, NSString *boot) {
    NSDictionary *current = powerdPreferences();
    if (![current[@"bootSessionUUID"] isEqual:boot] || ![current[@"policies"] isEqual:original])
        return fail(@"Native policies changed during preparation; retry without overwriting the newer policy.");
    CFPreferencesSetValue(CFSTR("policies"), (__bridge CFPropertyListRef)replacement, PolicyDomain,
        kCFPreferencesAnyUser, kCFPreferencesCurrentHost);
    if (!CFPreferencesSynchronize(PolicyDomain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost) ||
        ![powerdPreferences()[@"policies"] isEqual:replacement])
        return fail(@"Could not verify the native policy flag update. Recovery journal retained.");
    return YES;
}
static pid_t singleProcess(const char *expected) {
    pid_t pids[8192];
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof pids);
    if (bytes <= 0 || (size_t)bytes >= sizeof pids) return -1;
    pid_t found = -1;
    for (size_t i = 0; i < (size_t)bytes / sizeof(pid_t); i++) {
        char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
        if (pids[i] > 1 && proc_pidpath(pids[i], path, sizeof path) > 0 && strcmp(path, expected) == 0) {
            if (found != -1) return -1;
            found = pids[i];
        }
    }
    return found;
}
static BOOL reloadPowerd(void) {
    const char *path = "/System/Library/CoreServices/powerd.bundle/powerd";
    pid_t old = singleProcess(path);
    if (old < 2 || kill(old, SIGHUP) != 0)
        return fail(@"Could not reload Apple's power service. Policy recovery journal retained.");
    for (int i = 0; i < 100; i++) {
        usleep(100000);
        pid_t fresh = singleProcess(path);
        if (fresh > 1 && fresh != old) {
            note(@"Reloaded Apple's power service to apply native policy flags.");
            return YES;
        }
    }
    return fail(@"Power service restart was not confirmed within 10 seconds. Recovery journal retained.");
}
static BOOL removeOwnedPolicy(NSMutableDictionary *state) {
    NSData *token=state[@"ownedToken"];
    if (!token) return YES;
    NSString *boot=bootSession();
    if (!boot) return fail(@"Cannot verify the boot session for policy recovery.");
    NSDictionary *prefs=powerdPreferences();
    if (!prefs) return fail(@"Cannot read the native policy recovery state.");
    if ([state[@"ownedBoot"] isEqual:boot] && [prefs[@"bootSessionUUID"] isEqual:boot]) {
        NSData *replacement=b27_ownedPolicyData(prefs[@"policies"],token,0,0,YES);
        if (!replacement) return fail(@"Native policy format changed; recovery journal retained.");
        if (![replacement isEqual:prefs[@"policies"]]) {
            state[@"ownedRemovalPending"]=@YES;
            if (!saveState(state) || !replacePolicyData(prefs[@"policies"],replacement,boot)) return NO;
        }
        if ([state[@"ownedRemovalPending"] boolValue] && !reloadPowerd()) return NO;
    }
    for (NSString *key in @[@"ownedToken",@"ownedBoot",@"ownedOwner",@"ownedRemovalPending",@"policyAttempts"])
        [state removeObjectForKey:key];
    return saveState(state);
}
static BOOL ensureOwnedPolicy(NSMutableDictionary *state, int target) {
    if (!daemonMode) return fail(@"Only the resident daemon may own a native policy.");
    /* A timed-out status command is not evidence that the lease disappeared.
     * Recheck immediately before repair, including after PowerUI changes. */
    NSString *liveOutput=registeredOutput();
    if (!b27_registeredPolicies(liveOutput))
        return fail(@"Native policy read-back is unavailable; the existing policy was left unchanged.");
    if (b27_ownedRegistered(liveOutput,target,getpid())) return YES;
    NSString *boot=bootSession();
    NSDictionary *prefs=powerdPreferences();
    if (!boot || !prefs) return fail(@"Cannot read the native policy boot session.");
    if (![prefs[@"bootSessionUUID"] isEqual:boot]) {
        NSArray *live=b27_registeredPolicies(registeredOutput());
        if (!live || live.count) return fail(@"Current-boot policy archive is not ready; live policies left unchanged.");
        /* powerd ignores archives from earlier boots. Initialize only when its
         * live policy list is empty, preserving unrelated preference keys. */
        NSData *empty=b27_emptyPolicyArchive();
        NSDictionary *current=powerdPreferences();
        if (!empty || ![current isEqual:prefs]) return fail(@"Native policies changed during boot initialization.");
        CFPreferencesSetMultiple((__bridge CFDictionaryRef)@{@"bootSessionUUID":boot,@"policies":empty},
            NULL,PolicyDomain,kCFPreferencesAnyUser,kCFPreferencesCurrentHost);
        if (!CFPreferencesSynchronize(PolicyDomain,kCFPreferencesAnyUser,kCFPreferencesCurrentHost))
            return fail(@"Cannot initialize the current-boot policy archive.");
        prefs=powerdPreferences();
        if (![prefs[@"bootSessionUUID"] isEqual:boot]) return fail(@"Policy boot session did not retain the current value.");
    }
    if (![state[@"ownedBoot"] isEqual:boot]) {
        [state removeObjectForKey:@"ownedToken"];
        [state removeObjectForKey:@"policyAttempts"];
    }
    if (!state[@"ownedToken"]) {
        uuid_t bytes; [NSUUID.UUID getUUIDBytes:bytes];
        state[@"ownedToken"]=[NSData dataWithBytes:bytes length:sizeof bytes];
    }
    NSData *replacement=b27_ownedPolicyData(prefs[@"policies"],state[@"ownedToken"],getpid(),target,NO);
    if (!replacement) return fail(@"Unsupported native policy archive or token conflict. No policy replaced.");
    id history=state[@"policyAttempts"] ?: @[];
    if (![history isKindOfClass:NSArray.class] || [history count]>3) return fail(@"Invalid restart history.");
    NSMutableArray *attempts=[NSMutableArray array];
    for (id value in history) {
        if (![value isKindOfClass:NSNumber.class]) return fail(@"Invalid restart history.");
        if (now()-[value doubleValue]<600) [attempts addObject:value];
    }
    if (attempts.count>=3 || (attempts.count && [state[@"ownedOwner"] intValue]==getpid() &&
                            now()-[attempts.lastObject doubleValue]<60))
        return fail(@"Native policy repair is waiting: at most one restart per minute and three per ten minutes.");
    [attempts addObject:@(now())]; state[@"policyAttempts"]=attempts;
    state[@"ownedBoot"]=boot; state[@"ownedOwner"]=@(getpid());
    /* The journal is written before the persistent policy. Its owner is this
     * live process, so macOS releases the lease automatically on process exit. */
    if (!saveState(state) || !replacePolicyData(prefs[@"policies"],replacement,boot) || !reloadPowerd()) return NO;
    double deadline=now()+5;
    do {
        if (b27_ownedRegistered(registeredOutput(),target,getpid())) return YES;
        usleep(100000);
    } while(now()<deadline);
    return fail(@"Native policy written but live registration did not confirm it; journal retained.");
}
static void wakeDaemon(NSDictionary *state) {
    pid_t pid=[state[@"daemonPID"] intValue];
    char path[PROC_PIDPATHINFO_MAXSIZE]={0};
    if (pid>1 && [state[@"daemonBoot"] isEqual:bootSession()] &&
        proc_pidpath(pid,path,sizeof path)>0 &&
        strcmp(path,"/Library/PrivilegedHelperTools/co.palokaj.battery.macos27/native-charge")==0)
        kill(pid,SIGUSR1);
}

static BOOL tick(NSMutableDictionary *state, BOOL immediate) {
    (void)immediate;
    if ([state[@"restorePending"] boolValue]) return restoreOriginal(state);
    if (![state[@"enabled"] boolValue]) return YES;
    if (!daemonMode) return fail(@"Native policy changes are performed by the resident daemon.");
    BatteryInfo b;
    if (!batteryInfo(&b)) return NO;
    int target=0;
    if (!b27_fixed_target([state[@"lower"] intValue], [state[@"upper"] intValue], &target))
        return fail(@"Saved range is unsupported. Choose one ceiling or stop maintenance.");
    state[@"holdTarget"]=@0; state[@"observedPercentage"]=@(b.percentage); state[@"observedAt"]=@(now());
    if (!CFPreferencesSynchronize(Domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost))
        return fail(@"Cannot read native charging preferences.");
    NSString *registration=registeredOutput();
    if (!b27_registeredPolicies(registration))
        return fail(@"Native policy read-back is unavailable; the existing policy was left unchanged.");
    BOOL applePolicy=NO;
    for (NSDictionary *row in b27_registeredPolicies(registration))
        if ([row[@"chargeSocLimitReason"] isEqual:@"manualChargeLimit"]) applePolicy=YES;
    /* PowerUI must not compete with the independently owned policy. Its
     * original settings were captured before maintenance was enabled. */
    if (preference(FeatureKey).intValue==1 || preference(LimitKey).intValue!=100 || applePolicy) {
        if (!saveState(state) || !writeTarget(100)) return NO;
        registration=registeredOutput();
        if (!b27_registeredPolicies(registration))
            return fail(@"Native policy read-back is unavailable after releasing PowerUI; retrying without a power-service restart.");
    }
    if (target==100) {
        if (!removeOwnedPolicy(state)) return NO;
    } else if (!b27_ownedRegistered(registration,target,getpid())) {
        if (!ensureOwnedPolicy(state,target)) return NO;
    }
    state[@"lastRequested"]=@(target); state[@"acknowledgedAt"]=@(now());
    [state removeObjectForKey:@"lastError"]; [state removeObjectForKey:@"pendingSince"];
    NSString *warning=enforcementWarning(b,target);
    if (warning) {
        if (![state[@"enforcementWarning"] isEqual:warning]) note(warning);
        state[@"enforcementWarning"]=warning;
    } else [state removeObjectForKey:@"enforcementWarning"];
    return saveState(state);
}

static NSString *rangeLabel(NSDictionary *state) {
    int l = [state[@"lower"] intValue], u = [state[@"upper"] intValue];
    return l == u ? [NSString stringWithFormat:@"%d", u] : [NSString stringWithFormat:@"%d-%d", l, u];
}
static BOOL status(NSDictionary *state, BOOL csv) {
    BatteryInfo b;
    if (!batteryInfo(&b)) return NO;
    NSString *remaining = b.minutes >= 0 ? [NSString stringWithFormat:@"%d:%02d", b.minutes / 60, b.minutes % 60] : @"unknown";
    NSString *label = rangeLabel(state);
    if (csv) {
        /* Original five-field GUI contract. Field four is the legacy forced-
         * discharge state, which this backend cannot infer. Do not falsely label
         * actual discharge as an explicitly requested forced-discharge job. */
        printf("%d,%s,%s,unknown,%s\n", b.percentage, remaining.UTF8String,
               !b.chargingKnown ? "unknown" : (b.charging ? "enabled" : "disabled"), label.UTF8String);
        return YES;
    }
    printf("Battery at %d%% (%s remaining), actual charging %s\n", b.percentage, remaining.UTF8String, !b.chargingKnown ? "unknown" : (b.charging ? "yes" : "no"));
    if ([state[@"enabled"] boolValue]) {
        /* The legacy GUI uses 'being maintained at' to identify an enabled
         * policy. Preserve that token without claiming hardware enforcement. */
        printf("Requested policy: battery being maintained at %s%% (configuration only)\n", label.UTF8String);
        printf("Policy: fixed ceiling; requested native ceiling: %d%%\n", [state[@"lastRequested"] intValue]);
    } else puts("Battery maintenance is stopped.");
    printf("External power: %s\n", !b.externalKnown ? "unknown" : (b.external ? "yes" : "no"));
    printf("macOS charge-to-full override: %s\n", !b.fullChargeOverrideKnown ? "unknown" :
           (b.fullChargeOverride ? "active" : "not reported"));
    if (b.currentKnown) printf("Battery amperage: %lld mA (reported)\n", (long long)b.currentMA);
    else puts("Battery amperage: unknown");
    if (b.instantKnown) printf("Battery instant amperage: %lld mA (reported)\n", (long long)b.instantMA);
    else puts("Battery instant amperage: unknown");
    if (b.externalKnown && b.external && b.chargingKnown && !b.charging &&
        b.currentKnown && b.instantKnown && b.currentMA == 0 && b.instantMA == 0)
        puts("Observation: AC available; both battery current readings are zero in this sample.");
    puts("Current readings are snapshots, not a guarantee of long-term battery rest.");
    NSString *registration = registeredOutput();
    NSArray *targets = registeredTargets(registration);
    if (targets) printf("powerd registered ceilings: %s\n", targets.count ? [targets componentsJoinedByString:@", "].UTF8String : "none");
    else puts("powerd registered ceilings: unknown (not verified)");
    if ([state[@"enabled"] boolValue] && [state[@"upper"] intValue] < 100) {
        printf("Native no-charge-to-full / no-drain flags: %s\n",
               b27_ownedRegistered(registration,[state[@"upper"] intValue],[state[@"daemonPID"] intValue]) ? "confirmed" : "pending / not verified");
        if (b.percentage > [state[@"upper"] intValue])
            puts("Battery is already above the ceiling. Normal battery use can lower it; this backend does not force a drain.");
    }
    if ([state[@"enabled"] boolValue] && !matchesTarget(targets, [state[@"lastRequested"] intValue]))
        puts("Verification: PENDING / MISMATCH. A saved setting is not proof of charge enforcement.");
    NSString *warning = [state[@"enabled"] boolValue] ? enforcementWarning(b, [state[@"upper"] intValue]) : nil;
    if (warning) printf("WARNING: %s\n", warning.UTF8String);
    if (state[@"lastError"]) fprintf(stderr, "WARNING: %s\n", [state[@"lastError"] UTF8String]);
    if ([state[@"restorePending"] boolValue]) fprintf(stderr, "WARNING: restoration pending; recovery snapshot retained.\n");
    return YES;
}

static int run(int argc, char *const *argv) {
    if (geteuid() != 0) { fputs("Run through the installed battery command; root access is required.\n", stderr); return 77; }
    if (argc < 2) { fputs("Missing command.\n", stderr); return 64; }
    NSString *cmd = [NSString stringWithUTF8String:argv[1]];
    NSSet *simple = [NSSet setWithArray:@[@"probe", @"tick", @"status", @"status_csv", @"stop", @"recover", @"diagnose", @"check-state"]];
    if (([simple containsObject:cmd] && argc != 2) ||
        (![simple containsObject:cmd] && ![cmd isEqualToString:@"maintain"])) {
        fputs("Unsupported command or extra arguments.\n", stderr); return 64;
    }
    int lower = 0, upper = 0;
    if ([cmd isEqualToString:@"maintain"]) {
        if (argc != 3 || !b27_parse_percent(argv[2], &upper)) {
            fputs("Use a single ceiling 1..100. Independent lower thresholds are unsupported.\n", stderr); return 64;
        }
        lower = upper;
    }
    if ([cmd isEqualToString:@"probe"]) {
        BatteryInfo b;
        if (!powerClient() || !batteryInfo(&b)) return 1;
        puts("Native client and battery telemetry are available. No charge-limit change was made.");
        puts("This probe does not prove that a below-80% target will be enforced.");
        return 0;
    }
    int lock = stateLock();
    if (lock < 0) return 1;
    NSMutableDictionary *state = readState();
    if (!state) { close(lock); return 1; }
    if ([cmd isEqualToString:@"check-state"]) {
        int target = 0;
        BOOL compatible = !state[@"operation"] && !state[@"strictOriginals"] && ![state[@"restorePending"] boolValue] &&
            (![state[@"enabled"] boolValue] || b27_fixed_target([state[@"lower"] intValue], [state[@"upper"] intValue], &target));
        flock(lock, LOCK_UN); close(lock);
        if (!compatible) { fail(@"Existing range, operation, or pending restore needs resolution before upgrade. Nothing changed."); return 1; }
        puts("Saved state is compatible with fixed-ceiling mode. No charging settings changed."); return 0;
    }
    if (state[@"operation"]) { flock(lock, LOCK_UN); close(lock); fail(@"A 0.2.0 operation is present; resolve it with that version before upgrading."); return 1; }
    BOOL ok = YES;
    if ([cmd isEqualToString:@"status"] || [cmd isEqualToString:@"status_csv"] || [cmd isEqualToString:@"diagnose"]) {
        ok = status(state, [cmd isEqualToString:@"status_csv"]);
        if ([cmd isEqualToString:@"diagnose"]) {
            printf("Native preferences: feature=%s; target=%s\n", (preference(FeatureKey).description ?: @"absent").UTF8String,
                   (preference(LimitKey).description ?: @"absent").UTF8String);
            printf("Recovery snapshot: %s; restore pending: %s\n", [state[@"hasOriginal"] boolValue] ? "present" : "none",
                   [state[@"restorePending"] boolValue] ? "yes" : "no");
            puts("--- pmset -g battlimit ---");
            puts((registeredOutput() ?: @"unavailable").UTF8String);
        }
    } else if ([cmd isEqualToString:@"stop"]) {
        ok = restoreOriginal(state);
        if (ok) puts("Maintenance stopped; original native preferences restored. Inspect battery status to verify behaviour.");
    } else if ([cmd isEqualToString:@"tick"]) {
        if (!daemonMode) ok=fail(@"Use the resident daemon for ticks.");
        else {
            state[@"daemonPID"]=@(getpid()); state[@"daemonBoot"]=bootSession() ?: @"unknown";
            ok=saveState(state) && tick(state,NO);
        }
    } else {
        if ([cmd isEqualToString:@"recover"]) {
            lower = [state[@"lower"] intValue]; upper = [state[@"upper"] intValue];
            int target = 0;
            if (!b27_fixed_target(lower, upper, &target)) ok = fail(@"Saved range is not supported. Choose a single ceiling explicitly.");
        }
        if (ok && !powerClient()) ok = NO;
        if (ok && [state[@"restorePending"] boolValue]) ok = restoreOriginal(state);
        if (ok) ok = captureOriginal(state);
        BatteryInfo b;
        if (ok) ok = batteryInfo(&b);
        if (ok) {
            if ([cmd isEqualToString:@"recover"]) { lower = [state[@"lower"] intValue]; upper = [state[@"upper"] intValue]; }
            BOOL same = [state[@"enabled"] boolValue] && [state[@"lower"] intValue] == lower && [state[@"upper"] intValue] == upper;
            state[@"lower"] = @(lower); state[@"upper"] = @(upper); state[@"enabled"] = @YES;
            if (!same) {
                state[@"chargingPhase"] = @(b.charging); state[@"holdTarget"] = @0;
                [state removeObjectForKey:@"policyAttempts"]; /* explicit user target change */
            }
            state[@"lastRequested"]=@(upper);
            ok = saveState(state);
            if (ok) wakeDaemon(state);
            if (ok) {
                printf("Requested maintenance at %s%%.\n", rangeLabel(state).UTF8String);
                puts("Run battery status to check powerd registration and actual charging.");
                if (upper == 100) puts("The background daemon will release the native ceiling.");
                else puts("This is a fixed ceiling with native no-charge-to-full and no-drain flags. Firmware controls restart hysteresis.");
            }
        }
    }
    if (!ok) {
        state[@"lastError"] = failure ?: @"Unknown backend failure";
        NSString *reason = failure;
        saveState(state);
        failure = reason;
    }
    flock(lock, LOCK_UN); close(lock);
    return ok ? 0 : 1;
}

static void daemonSignal(int signal) {
    if (signal==SIGTERM || signal==SIGINT) daemonStop=1;
    daemonWake=1;
}
int main(int argc, char **argv) {
    umask(0077);
    setenv("HOME", "/var/root", 1);
    setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1);
    if (argc==2 && strcmp(argv[1],"daemon")==0) {
        if (geteuid()!=0) return 77;
        daemonMode=YES;
        signal(SIGUSR1,daemonSignal); signal(SIGTERM,daemonSignal); signal(SIGINT,daemonSignal);
        char *tickArgs[]={argv[0],"tick",NULL};
        while(!daemonStop) {
            daemonWake=0;
            @autoreleasepool {
                failure=nil;
                int code=run(2,tickArgs);
                if (code && failure) fprintf(stderr,"ERROR: %s\n",failure.UTF8String);
            }
            for(int i=0;i<15 && !daemonWake && !daemonStop;i++) sleep(1);
        }
        /* powerd monitors this PID and cancels its native lease on exit. */
        return 0;
    }
    @autoreleasepool {
        int code=run(argc,argv);
        if (code && failure) fprintf(stderr,"ERROR: %s\n",failure.UTF8String);
        return code;
    }
}
