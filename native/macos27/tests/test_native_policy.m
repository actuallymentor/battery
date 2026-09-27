/* SPDX-License-Identifier: MIT
 * Pure archive tests: no battery APIs, preferences or system services. */
#import "../src/native-policy.h"
#include <assert.h>
static NSArray *records(NSData *data) {NSArray*r=nil;assert(b27_readPolicyArchive(data,&r));return r;}
int main(void){@autoreleasepool{
 uuid_t raw;[NSUUID.UUID getUUIDBytes:raw];NSData*token=[NSData dataWithBytes:raw length:16];
 NSData*empty=b27_emptyPolicyArchive();assert(records(empty).count==0);
 NSData*a=b27_ownedPolicyData(empty,token,1234,55,NO);assert(a);
 NSDictionary*p=records(a)[0][@"object"];
 assert([p[@"soclimit"] isEqual:@55]&&[p[@"owner"] isEqual:@1234]);
 assert([p[@"drain"] isEqual:@NO]&&[p[@"noChargeToFull"] isEqual:@YES]);
 assert([b27_ownedPolicyData(a,token,1234,55,NO) isEqual:a]);
 NSData*changed=b27_ownedPolicyData(a,token,1234,60,NO);
 assert([records(changed)[0][@"object"][@"soclimit"] isEqual:@60]);
 NSData*restarted=b27_ownedPolicyData(changed,token,5678,60,NO);
 assert([records(restarted)[0][@"object"][@"owner"] isEqual:@5678]);
 assert(records(restarted).count==1);
 assert(records(b27_ownedPolicyData(restarted,token,0,0,YES)).count==0);
 assert([b27_ownedPolicyData(empty,token,0,0,YES) isEqual:empty]);
 assert(!b27_ownedPolicyData(a,token,0,55,NO));
 assert(!b27_ownedPolicyData(a,token,1234,100,NO));
 assert(!b27_ownedPolicyData(a,[NSData data],1234,55,NO));
 // Preserve an unrelated token and refuse a token with another client's reason.
 uuid_t raw2;[NSUUID.UUID getUUIDBytes:raw2];NSData*token2=[NSData dataWithBytes:raw2 length:16];
 NSData*two=b27_ownedPolicyData(a,token2,999,80,NO);assert(records(two).count==2);
 NSData*removed=b27_ownedPolicyData(two,token,0,0,YES);
 assert(records(removed).count==1&&[records(removed)[0][@"token"] isEqual:token2]);
 NSArray*rs=nil;NSMutableDictionary*archive=b27_readPolicyArchive(a,&rs);
 NSMutableArray*objects=archive[@"$objects"];
 [objects addObject:@"foreign-client"];
 rs[0][@"object"][@"reason"]=b27_archiveUID(objects.count-1);
 NSData*foreign=[NSPropertyListSerialization dataWithPropertyList:archive format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
 assert(!b27_ownedPolicyData(foreign,token,1234,55,NO));
 assert(!b27_ownedPolicyData(foreign,token,0,0,YES));
 assert(!b27_readPolicyArchive([@"invalid" dataUsingEncoding:NSUTF8StringEncoding],NULL));
 archive=b27_readPolicyArchive(a,&rs);rs[0][@"object"][@"drain"]=@2;
 assert(!b27_readPolicyArchive([NSPropertyListSerialization dataWithPropertyList:archive format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL],NULL));
 archive=b27_readPolicyArchive(a,&rs);rs[0][@"object"][@"token"]=@{@"nested":rs[0][@"object"][@"token"]};
 assert(!b27_readPolicyArchive([NSPropertyListSerialization dataWithPropertyList:archive format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL],NULL));
 NSString*row=@"{Terminated=0;chargeSocLimitSoc=55;chargeSocLimitDrain=0;chargeSocLimitNoChargeToFull=1;chargeSocLimitReason=\"co.palokaj.battery.macos27\";chargeSocLimitOwner=%d;}";
 NSString*live=[NSString stringWithFormat:@"Battery level limits:\n(%@,%@)",[NSString stringWithFormat:row,1234],[NSString stringWithFormat:row,0]];
 assert(b27_ownedRegistered(live,55,1234));assert(!b27_ownedRegistered(live,60,1234));assert(!b27_ownedRegistered(live,55,999));
 assert(!b27_ownedRegistered([live stringByReplacingOccurrencesOfString:@"Drain=0" withString:@"Drain=1"],55,1234));
 assert(!b27_ownedRegistered(@"No battery level limits set",55,1234));
 // Unknown read-back must stay distinct from a confirmed empty policy list.
 assert(!b27_registeredPolicies(nil));
 assert(!b27_registeredPolicies(@""));
 assert(!b27_registeredPolicies(@"Battery level limits:\ninvalid"));
 assert(!b27_registeredPolicies(@"Battery level limits:\n({valid=0;},invalid)"));
 assert(b27_registeredPolicies(@"No battery level limits set").count==0);
 puts("PASS: owned native lease, target/owner changes, cancellation, isolation and malformed archives.");
}return 0;}
