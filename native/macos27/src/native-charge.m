/* SPDX-License-Identifier: MIT
 * Local, experimental compatibility backend for actuallymentor/battery 1.4.0.
 * Fixed-ceiling draft 0.1.1. Not an upstream release. Runtime capability probe.
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
#include "policy.h"

static NSString *const StateDir = @"/private/var/db/co.palokaj.battery.macos27";
static NSString *const StateFile = @"/private/var/db/co.palokaj.battery.macos27/state.plist";
static CFStringRef const Domain = CFSTR("com.apple.smartcharging.topoffprotection");
static CFStringRef const FeatureKey = CFSTR("MCLFeatureState");
static CFStringRef const LimitKey = CFSTR("mclLimitValue");
static const char *ReloadNotification = "com.apple.smartcharging.defaultschanged";
static NSString *failure = nil;

/* Declarations only: these selectors are dynamically provided by PowerUI.
 * Every selector is checked before use. No Apple private headers are shipped.
 */
@interface NSObject (B27PowerUI)
- (id)initWithClientName:(NSString *)name;
- (BOOL)isMCLSupported;
- (uint64_t)isMCLCurrentlyEnabled:(NSError **)error;
- (BOOL)enableMCL:(NSError **)error;
- (BOOL)disableMCL:(NSError **)error;
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
    if (!saveState(state) || !disableViaAgent()) return NO;
    setPreference(FeatureKey, feature);
    setPreference(LimitKey, limit);
    if (!flushPreferences()) return NO;
    if ((feature && ![preference(FeatureKey) isEqual:feature]) ||
        (!feature && preference(FeatureKey)) ||
        (limit && ![preference(LimitKey) isEqual:limit]) || (!limit && preference(LimitKey)))
        return fail(@"Original native preferences could not be verified after restoration.");
    for (NSString *key in @[@"originalFeature", @"originalLimit", @"hasOriginal", @"restorePending",
                            @"lastRequested", @"requestedAt", @"pendingSince", @"lastError", @"manual"]) {
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
} BatteryInfo;

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

static BOOL tick(NSMutableDictionary *state, BOOL immediate) {
    if ([state[@"restorePending"] boolValue]) return restoreOriginal(state);
    if (![state[@"enabled"] boolValue]) return YES;
    BatteryInfo b;
    if (!batteryInfo(&b)) return NO;
    int target = 0;
    if (!b27_fixed_target([state[@"lower"] intValue], [state[@"upper"] intValue], &target))
        return fail(@"Saved range is unsupported. No target changed. Use battery maintain PERCENT or battery maintain stop.");
    /* Migration only: the old schema's phase fields no longer choose targets. */
    state[@"holdTarget"] = @0;
    state[@"observedPercentage"] = @(b.percentage);
    state[@"observedAt"] = @(now());
    NSArray *targets = registeredTargets(registeredOutput());
    BOOL acknowledged = matchesTarget(targets, target);
    BOOL changed = !state[@"lastRequested"] || [state[@"lastRequested"] intValue] != target;
    if (!CFPreferencesSynchronize(Domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
        return fail(@"Cannot refresh native charge-limit preferences.");
    BOOL prefsMatch = target == 100 ? preference(FeatureKey).intValue != 1 :
        (preference(FeatureKey).intValue == 1 && preference(LimitKey).intValue == target);
    /* Re-notify at most once per minute if the asynchronous agent has not caught up. */
    if (changed || !prefsMatch || immediate || (!acknowledged && now() - [state[@"requestedAt"] doubleValue] >= 60)) {
        if (!saveState(state) || !writeTarget(target)) return NO;
        state[@"lastRequested"] = @(target);
        state[@"requestedAt"] = @(now());
        if (changed || !state[@"pendingSince"]) state[@"pendingSince"] = @(now());
        note([NSString stringWithFormat:@"Requested fixed native ceiling %d%%; observed %d%%. Enforcement is asynchronous.",
              target, b.percentage]);
    }
    if (acknowledged) {
        state[@"acknowledgedAt"] = @(now());
        [state removeObjectForKey:@"pendingSince"];
        [state removeObjectForKey:@"lastError"];
    } else if (state[@"pendingSince"] && now() - [state[@"pendingSince"] doubleValue] >= 120) {
        NSString *warning = @"powerd has not confirmed the requested limit. Do not assume charging is limited. Run battery diagnose.";
        if (![state[@"lastError"] isEqualToString:warning]) note(warning);
        state[@"lastError"] = warning;
    }
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
        printf("Your battery is currently being maintained at %s%% (requested policy)\n", label.UTF8String);
        printf("Policy: fixed ceiling; requested native ceiling: %d%%\n", [state[@"lastRequested"] intValue]);
    } else puts("Battery maintenance is stopped.");
    printf("External power: %s\n", !b.externalKnown ? "unknown" : (b.external ? "yes" : "no"));
    if (b.currentKnown) printf("Battery amperage: %lld mA (reported)\n", (long long)b.currentMA);
    else puts("Battery amperage: unknown");
    if (b.instantKnown) printf("Battery instant amperage: %lld mA (reported)\n", (long long)b.instantMA);
    else puts("Battery instant amperage: unknown");
    if (b.externalKnown && b.external && b.chargingKnown && !b.charging &&
        b.currentKnown && b.instantKnown && b.currentMA == 0 && b.instantMA == 0)
        puts("Observation: AC available; both battery current readings are zero in this sample.");
    puts("Current readings are snapshots, not a guarantee of long-term battery rest.");
    NSArray *targets = registeredTargets(registeredOutput());
    if (targets) printf("powerd registered ceilings: %s\n", targets.count ? [targets componentsJoinedByString:@", "].UTF8String : "none");
    else puts("powerd registered ceilings: unknown (not verified)");
    if ([state[@"enabled"] boolValue] && !matchesTarget(targets, [state[@"lastRequested"] intValue]))
        puts("Verification: PENDING / MISMATCH. A saved setting is not proof of charge enforcement.");
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
        BOOL compatible = !state[@"operation"] && ![state[@"restorePending"] boolValue] &&
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
        ok = tick(state, NO);
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
            if (!same) { state[@"chargingPhase"] = @(b.charging); state[@"holdTarget"] = @0; }
            ok = saveState(state) && tick(state, YES);
            if (ok) {
                printf("Requested maintenance at %s%%.\n", rangeLabel(state).UTF8String);
                puts("Run battery status to check powerd registration and actual charging.");
                puts("This is a fixed ceiling. Firmware controls restart hysteresis and may drain toward a lower target.");
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

int main(int argc, char **argv) {
    umask(0077);
    setenv("HOME", "/var/root", 1);
    setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1);
    @autoreleasepool {
        int code = run(argc, argv);
        if (code && failure) fprintf(stderr, "ERROR: %s\n", failure.UTF8String);
        return code;
    }
}
