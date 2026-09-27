/* SPDX-License-Identifier: MIT
 * Pure, bounded parser for the powerd policy archive observed on macOS 27.
 * Never instantiate archived classes or replace unrelated policies. UID
 * references stay intact when the property list is written back as binary.
 */
#ifndef BATTERY27_NATIVE_POLICY_H
#define BATTERY27_NATIVE_POLICY_H
#import <Foundation/Foundation.h>
#include <limits.h>

static inline id b27_archiveObject(id ref, NSArray *objects) {
    if (!ref) return nil;
    if ([ref isKindOfClass:NSDictionary.class] || [ref isKindOfClass:NSArray.class]) return nil;
    /* Foundation exposes archive UIDs as opaque CF objects. Its XML encoder
     * renders them as CF$UID; use that representation without a private API. */
    NSData *xml = [NSPropertyListSerialization dataWithPropertyList:ref
        format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    NSString *s = xml ? [[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding] : nil;
    if (!s) return nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:
        @"<dict>\\s*<key>CF\\$UID</key>\\s*<integer>([0-9]+)</integer>\\s*</dict>"
        options:0 error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0,s.length)];
    if (!m) return nil;
    NSString *number = [s substringWithRange:[m rangeAtIndex:1]];
    if (number.length > 9) return nil;
    NSUInteger index = (NSUInteger)number.longLongValue;
    return index < objects.count ? objects[index] : nil;
}
static inline NSString *b27_archiveClass(NSDictionary *o, NSArray *objects) {
    id cls = b27_archiveObject(o[@"$class"], objects);
    return [cls isKindOfClass:NSDictionary.class] && [cls[@"$classname"] isKindOfClass:NSString.class]
        ? cls[@"$classname"] : nil;
}
static inline BOOL b27_numberInRange(id value, int low, int high) {
    return [value isKindOfClass:NSNumber.class] && [value doubleValue] >= low &&
        [value doubleValue] <= high && [value doubleValue] == [value intValue];
}
static inline NSMutableDictionary *b27_readPolicyArchive(NSData *data, NSArray **records) {
    if (![data isKindOfClass:NSData.class] || data.length > 1048576) return nil;
    id archive = [NSPropertyListSerialization propertyListWithData:data
        options:NSPropertyListMutableContainersAndLeaves format:NULL error:NULL];
    if (![archive isKindOfClass:NSMutableDictionary.class] ||
        ![archive[@"$archiver"] isEqual:@"NSKeyedArchiver"] ||
        ![archive[@"$version"] isEqual:@100000]) return nil;
    NSArray *objects = archive[@"$objects"];
    id top = archive[@"$top"];
    if (![objects isKindOfClass:NSArray.class] || objects.count > 1024 ||
        ![top isKindOfClass:NSDictionary.class]) return nil;
    id root = b27_archiveObject(top[@"root"], objects);
    if (![root isKindOfClass:NSDictionary.class]) return nil;
    NSString *cls = b27_archiveClass(root, objects);
    if (!([cls isEqual:@"NSMutableArray"] || [cls isEqual:@"NSArray"])) return nil;
    NSArray *refs = root[@"NS.objects"];
    if (![refs isKindOfClass:NSArray.class] || refs.count > 64) return nil;
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *tokens = [NSMutableSet set];
    for (id ref in refs) {
        id o = b27_archiveObject(ref, objects);
        if (![o isKindOfClass:NSMutableDictionary.class] ||
            ![b27_archiveClass(o, objects) isEqual:@"ChargeCtrlPolicy"]) return nil;
        for (NSString *key in @[@"drain", @"noChargeToFull", @"isEndOfCharge", @"terminated"])
            if (!b27_numberInRange(o[key], 0, 1)) return nil;
        if (!b27_numberInRange(o[@"soclimit"], 1, 100) ||
            !b27_numberInRange(o[@"owner"], 0, INT_MAX)) return nil;
        id reason = b27_archiveObject(o[@"reason"], objects);
        id token = b27_archiveObject(o[@"token"], objects);
        if (![reason isKindOfClass:NSString.class] || ![token isKindOfClass:NSDictionary.class] ||
            ![b27_archiveClass(token, objects) isEqual:@"NSUUID"]) return nil;
        id uuid = token[@"NS.uuidbytes"];
        if (![uuid isKindOfClass:NSData.class] || [uuid length] != 16 || [tokens containsObject:uuid]) return nil;
        [tokens addObject:uuid];
        [result addObject:@{@"object":o, @"token":uuid, @"reason":reason}];
    }
    if (records) *records = result;
    return archive;
}


static NSString *const B27PolicyReason = @"co.palokaj.battery.macos27";
static inline id b27_archiveUID(NSUInteger index) {
    NSString *xml = [NSString stringWithFormat:@"<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CF$UID</key><integer>%lu</integer></dict></plist>",(unsigned long)index];
    return [NSPropertyListSerialization propertyListWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]
        options:0 format:NULL error:NULL];
}
static inline NSData *b27_emptyPolicyArchive(void) {
    return [NSKeyedArchiver archivedDataWithRootObject:[NSMutableArray array]
        requiringSecureCoding:YES error:NULL];
}
/* Edit only a journaled token with our reason. Other policies are preserved.
 * A live daemon owns the lease; powerd's process-exit monitor releases it if
 * that daemon exits. No PID belonging to another process is impersonated. */
static inline NSData *b27_ownedPolicyData(NSData *data, NSData *token, int owner, int target, BOOL remove) {
    if (![token isKindOfClass:NSData.class] || token.length != 16 ||
        (!remove && (owner < 2 || target < 1 || target >= 100))) return nil;
    NSArray *records = nil;
    NSMutableDictionary *archive = b27_readPolicyArchive(data,&records);
    if (!archive) return nil;
    NSMutableArray *objects = archive[@"$objects"];
    NSMutableDictionary *root = b27_archiveObject(archive[@"$top"][@"root"],objects);
    NSMutableArray *refs = root[@"NS.objects"];
    NSMutableDictionary *policy = nil;
    for (NSDictionary *r in records) {
        if ([r[@"token"] isEqual:token]) {
            if (![r[@"reason"] isEqual:B27PolicyReason]) return nil;
            policy = r[@"object"];
        }
    }
    if (remove) {
        if (!policy) return data;
        for (NSInteger i=(NSInteger)refs.count-1;i>=0;i--)
            if (b27_archiveObject(refs[(NSUInteger)i],objects)==policy)
                [refs removeObjectAtIndex:(NSUInteger)i];
    } else {
        if (!policy) {
            if (objects.count > 1000 || refs.count >= 64) return nil;
            NSUInteger classIndex=objects.count;
            [objects addObject:@{@"$classname":@"ChargeCtrlPolicy",@"$classes":@[@"ChargeCtrlPolicy",@"NSObject"]}];
            NSUInteger uuidClass=objects.count;
            [objects addObject:@{@"$classname":@"NSUUID",@"$classes":@[@"NSUUID",@"NSObject"]}];
            NSUInteger uuidIndex=objects.count;
            [objects addObject:@{@"$class":b27_archiveUID(uuidClass),@"NS.uuidbytes":token}];
            NSUInteger reasonIndex=objects.count;
            [objects addObject:B27PolicyReason];
            policy=[@{@"$class":b27_archiveUID(classIndex),@"token":b27_archiveUID(uuidIndex),
                       @"reason":b27_archiveUID(reasonIndex)} mutableCopy];
            [refs addObject:b27_archiveUID(objects.count)];
            [objects addObject:policy];
        }
        if ([policy[@"owner"] isEqual:@(owner)] && [policy[@"soclimit"] isEqual:@(target)] &&
            [policy[@"drain"] isEqual:@NO] && [policy[@"noChargeToFull"] isEqual:@YES] &&
            [policy[@"isEndOfCharge"] isEqual:@YES] && [policy[@"terminated"] isEqual:@NO]) return data;
        policy[@"owner"]=@(owner); policy[@"soclimit"]=@(target);
        policy[@"drain"]=@NO; policy[@"noChargeToFull"]=@YES;
        policy[@"isEndOfCharge"]=@YES; policy[@"terminated"]=@NO;
    }
    return [NSPropertyListSerialization dataWithPropertyList:archive
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
}
static inline NSArray *b27_registeredPolicies(NSString *output) {
    if (!output) return nil;
    if ([output rangeOfString:@"No battery level limits set" options:NSCaseInsensitiveSearch].location != NSNotFound) return @[];
    NSRange newline=[output rangeOfString:@"\n"];
    if (newline.location==NSNotFound) return nil;
    id rows=[NSPropertyListSerialization propertyListWithData:[[output substringFromIndex:NSMaxRange(newline)] dataUsingEncoding:NSUTF8StringEncoding]
        options:0 format:NULL error:NULL];
    if (![rows isKindOfClass:NSArray.class] || [rows count]>64) return nil;
    for(id row in rows) if(![row isKindOfClass:NSDictionary.class]) return nil;
    return rows;
}
static inline BOOL b27_ownedRegistered(NSString *output, int target, int owner) {
    if(owner<2 || target<1 || target>=100) return NO;
    BOOL own=NO,effective=NO;
    NSString *pid=[NSString stringWithFormat:@"%d",owner],*ceiling=[NSString stringWithFormat:@"%d",target];
    for(NSDictionary *r in b27_registeredPolicies(output)) {
        BOOL isOwn=[r[@"chargeSocLimitOwner"] isEqual:pid];
        BOOL isEffective=[r[@"chargeSocLimitOwner"] isEqual:@"0"];
        if(!isOwn && !isEffective) continue;
        if(![r[@"chargeSocLimitSoc"] isEqual:ceiling] || ![r[@"chargeSocLimitDrain"] isEqual:@"0"] ||
           ![r[@"chargeSocLimitNoChargeToFull"] isEqual:@"1"] || ![r[@"Terminated"] isEqual:@"0"] ||
           ![r[@"chargeSocLimitReason"] isEqual:B27PolicyReason]) return NO;
        own |= isOwn; effective |= isEffective;
    }
    return own && effective;
}
#endif
