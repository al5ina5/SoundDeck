#import "../Shared/SDProtocol.h"
#import "../Shared/SDIdentity.h"
#define PROC_PIDPATHINFO_MAXSIZE 4096
extern int proc_listallpids(void *, int);
extern int proc_pidpath(int, void *, uint32_t);
#include <signal.h>
#include <unistd.h>
#include <sys/resource.h>
#include <grp.h>
static NSMutableDictionary<NSString *,NSNumber *> *tokens;
static NSDictionary *preferences;
static dispatch_source_t serviceTimer;
static NSMutableDictionary *metadataCache;
static NSMutableDictionary<NSNumber *,NSNumber *> *clientTokens;
static NSMutableDictionary<NSNumber *,NSNumber *> *detailTokens;
static NSMutableDictionary<NSNumber *,NSString *> *webOwners;
static NSMutableDictionary<NSString *,NSNumber *> *published;
static NSMutableSet<NSString *> *relayedOwners;
static int phaseToken;
static NSString *rootlessApplications;
static void phase(unsigned step,pid_t pid) { notify_set_state(phaseToken,((uint64_t)step<<32)|(uint32_t)pid); }
static uint64_t publish(NSString *name, uint64_t state) {
    if(published[name] && published[name].unsignedLongLongValue==state) return state;
    NSNumber *n=tokens[name]; int t;
    if(!n) { if(notify_register_check(name.UTF8String,&t)) return 0; tokens[name]=@(t); }
    else t=n.intValue;
    if(notify_set_state(t,state)) return 0;
    published[name]=@(state); notify_post(name.UTF8String); return state;
}
static void watchOwner(NSString *bid) {
    if([relayedOwners containsObject:bid]) return;
    [relayedOwners addObject:bid]; int watcher;
    notify_register_dispatch(SDGainName(bid).UTF8String,&watcher,dispatch_get_main_queue(),^(int token){ @autoreleasepool {
        NSNumber *check=tokens[SDGainName(bid)]; uint64_t state=0; if(!check || notify_get_state(check.intValue,&state)) return;
        for(NSNumber *pid in webOwners) if([webOwners[pid] isEqual:bid]) publish(SDProcessGainName(pid.intValue),state|(1ULL<<13));
    } });
}
static void reload(void) {
    preferences=SDReadPrefs();
    publish(@SD_GLOBAL, SDGlobalState(preferences));
    NSDictionary *apps=preferences[@"apps"];
    NSMutableSet *ids=[NSMutableSet setWithArray:apps.allKeys ?: @[]];
    for(NSString *key in tokens.allKeys) if([key hasPrefix:@"com.alsinas.sounddeck.gain."]) [ids addObject:[key substringFromIndex:@"com.alsinas.sounddeck.gain.".length]];
    for(NSString *bid in ids) publish(SDGainName(bid),SDConfig(preferences,apps[bid]));
    for(NSNumber *pid in webOwners) { NSString *bid=webOwners[pid]; publish(SDProcessGainName(pid.intValue),SDConfig(preferences,apps[bid])|(1ULL<<13)); }
    // Injection is automatic; the service never edits an enrollment filter or regains root.
}
static void snapshot(void) {
    double began=NSDate.date.timeIntervalSince1970;
    phase(1,0);
    if(metadataCache.count>512) [metadataCache removeAllObjects];
    NSNumber *global=tokens[@SD_GLOBAL]; if(global) notify_set_state(global.intValue,SDGlobalState(preferences));
    int count=proc_listallpids(NULL,0);
    if(count<=0 || count>65536) return;
    NSMutableData *pids=[NSMutableData dataWithLength:(count+128)*sizeof(pid_t)];
    int actual=proc_listallpids(pids.mutableBytes,(int)pids.length);
    NSMutableSet *livePIDs=[NSMutableSet new];
    NSMutableArray *clients=[NSMutableArray new];
    NSMutableDictionary *paths=[NSMutableDictionary new],*identities=[NSMutableDictionary new],*coalitionOwners=[NSMutableDictionary new];
    // Use kernel resource AND jetsam coalition IDs, never the last foreground/now-playing app.
    // A shared or ambiguous web process remains at unity rather than controlling the wrong app.
    for(int i=0;i<MIN(actual,(int)pids.length/(int)sizeof(pid_t));i++) {
        pid_t pid=((pid_t *)pids.mutableBytes)[i]; if(pid<=0) continue;
        char path[4096]={0}; if(proc_pidpath(pid,path,sizeof(path))<=0) continue;
        NSString *exe=@(path);
        BOOL app=[exe hasPrefix:@"/Applications/"] || [exe hasPrefix:@"/private/var/containers/Bundle/Application/"] || [exe hasPrefix:@"/var/containers/Bundle/Application/"] || [exe hasPrefix:rootlessApplications];
        BOOL web=[exe containsString:@"/System/"] && [exe containsString:@"com.apple.WebKit."];
        if(!app && !web) continue; paths[@(pid)]=exe;
        NSRange r=[exe rangeOfString:@".app/"]; if(!app || r.location==NSNotFound) continue;
        NSString *bundle=[exe substringToIndex:r.location+4]; NSDictionary *info=metadataCache[bundle];
        if(!info) { info=[NSDictionary dictionaryWithContentsOfFile:[bundle stringByAppendingPathComponent:@"Info.plist"]]; if(info) metadataCache[bundle]=info; }
        NSString *bid=info[@"CFBundleIdentifier"]; if(SDExcludedBundle(bid)) continue;
        identities[@(pid)]=info;
        NSString *key=SDCoalitionKey(pid); if(!key) continue;
        NSMutableDictionary *owners=coalitionOwners[key]; if(!owners) coalitionOwners[key]=owners=[NSMutableDictionary new]; owners[bid]=info;
    }
    for(int i=0;i<MIN(actual,(int)pids.length/(int)sizeof(pid_t));i++) {
        pid_t pid=((pid_t *)pids.mutableBytes)[i]; if(pid<=0) continue;
        [livePIDs addObject:@(pid)];
        NSString *exe=paths[@(pid)]; if(!exe) continue;
        phase(2,pid);
        phase(3,pid);
        int token=0; uint64_t state=0; NSNumber *cached=clientTokens[@(pid)];
        if(cached) token=cached.intValue;
        else if(!notify_register_check(SDClientName(pid).UTF8String,&token)) clientTokens[@(pid)]=@(token);
        if(clientTokens[@(pid)] && notify_get_state(token,&state)) { notify_cancel(token); [clientTokens removeObjectForKey:@(pid)]; state=0; }
        if(!SDFresh(state)) continue;
        phase(4,pid);
        NSDictionary *info=identities[@(pid)]; BOOL web=(state&(1ULL<<63))!=0,verified=!web;
        if(web && [exe containsString:@"/System/"] && [exe containsString:@"com.apple.WebKit."]) {
            NSString *key=SDCoalitionKey(pid); NSDictionary *owners=key?coalitionOwners[key]:nil;
            verified=owners.count==1;
            info=verified?owners.allValues.firstObject:@{@"CFBundleIdentifier":@"com.apple.WebKit.unattributed",@"CFBundleDisplayName":@"Web audio · owner unavailable"};
            if(verified) { webOwners[@(pid)]=info[@"CFBundleIdentifier"]; watchOwner(info[@"CFBundleIdentifier"]); } else [webOwners removeObjectForKey:@(pid)];
            publish(SDProcessGainName(pid),verified?(SDConfig(preferences,preferences[@"apps"][info[@"CFBundleIdentifier"]])|(1ULL<<13)):0);
        }
        NSString *bid=info[@"CFBundleIdentifier"]; if(!bid) continue;
        NSDictionary *entry=preferences[@"apps"][bid];
        NSString *gainName=SDGainName(bid);
        uint64_t expected=SDConfig(preferences,entry);
        if(!tokens[gainName]) publish(gainName,expected);
        uint64_t details=0; int dt;
        NSNumber *dn=detailTokens[@(pid)];
        if(dn) dt=dn.intValue;
        else if(!notify_register_check([[SDClientName(pid) stringByAppendingString:@".details"] UTF8String],&dt)) detailTokens[@(pid)]=@(dt);
        if(detailTokens[@(pid)]) notify_get_state(dt,&details);
        [clients addObject:@{@"bundleID":bid,@"name":info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: bid,
          @"pid":@(pid),@"active":@((state&1)!=0),@"path":SDPathName((state>>1)&7),
          @"gain":@(((state>>4)&1023)/1000.),@"inputRMS":@(((state>>14)&65535)/65535.),
          @"outputRMS":@(((state>>30)&65535)/65535.),@"metered":@(((state>>1)&7)==1 || ((state>>1)&7)==7),@"controllable":@(verified && !(state&(1ULL<<62)) && ((state>>1)&7)!=6),
          @"webProcess":@(web),@"ownerVerified":@(verified),@"apiMask":@(details&65535),@"nativeVolume":@(((details>>16)&65535)/10000.),@"nativeBase":@(((details>>32)&65535)/10000.),@"nativeObjects":@(details>>48)}];
    }
    for(NSNumber *pid in clientTokens.allKeys) if(![livePIDs containsObject:pid]) { notify_cancel(clientTokens[pid].intValue); [clientTokens removeObjectForKey:pid]; }
    for(NSNumber *pid in detailTokens.allKeys) if(![livePIDs containsObject:pid]) { notify_cancel(detailTokens[pid].intValue); [detailTokens removeObjectForKey:pid]; [webOwners removeObjectForKey:pid]; }
    struct rusage usage={0}; getrusage(RUSAGE_SELF,&usage);
    double cpu=usage.ru_utime.tv_sec+usage.ru_utime.tv_usec/1e6+usage.ru_stime.tv_sec+usage.ru_stime.tv_usec/1e6;
    NSDictionary *status=@{@"version":SD_VERSION,@"timestamp":@(NSDate.date.timeIntervalSince1970),@"clients":clients,
      @"servicePID":@(getpid()),@"serviceCpuSeconds":@(cpu),@"servicePeakRSSBytes":@(usage.ru_maxrss),
      @"discoveryDurationMs":@((NSDate.date.timeIntervalSince1970-began)*1000),
      @"disabled":@([preferences[@"disabled"] boolValue])};
    phase(5,0); [status writeToFile:SD_STATUS atomically:YES]; phase(0,0);
}
int main(void) { @autoreleasepool {
    tokens=[NSMutableDictionary new];
    metadataCache=[NSMutableDictionary new];
    clientTokens=[NSMutableDictionary new];
    detailTokens=[NSMutableDictionary new]; webOwners=[NSMutableDictionary new]; published=[NSMutableDictionary new]; relayedOwners=[NSMutableSet new];
    rootlessApplications=[[@"/var/jb/Applications" stringByResolvingSymlinksInPath] stringByAppendingString:@"/"];
    if(getuid()==0) { setgroups(0,NULL); if(setgid(501) || setuid(501)) return 1; }
    notify_register_check("com.alsinas.sounddeck.service-phase",&phaseToken);
    [[NSFileManager defaultManager] createDirectoryAtPath:SD_DIR withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    @autoreleasepool { reload(); }
    int t; notify_register_dispatch(SD_CHANGED,&t,dispatch_get_main_queue(),^(int token){ @autoreleasepool { reload(); snapshot(); } });
    serviceTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(serviceTimer,DISPATCH_TIME_NOW,NSEC_PER_SEC,200*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(serviceTimer,^{ @autoreleasepool { snapshot(); } }); dispatch_resume(serviceTimer);
    dispatch_main();
} }
