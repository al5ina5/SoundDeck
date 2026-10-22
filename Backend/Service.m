#import "../Shared/SDProtocol.h"
#define PROC_PIDPATHINFO_MAXSIZE 4096
extern int proc_listallpids(void *, int);
extern int proc_pidpath(int, void *, uint32_t);
#include <signal.h>
#include <unistd.h>
#include <sys/resource.h>
static NSMutableDictionary<NSString *,NSNumber *> *tokens;
static NSDictionary *preferences;
static dispatch_source_t serviceTimer;
static NSSet *lastEnrollment,*knownInstalled;
static NSMutableDictionary *metadataCache;
static NSMutableDictionary<NSNumber *,NSNumber *> *clientTokens;
static int phaseToken;
static NSString *rootlessApplications;
static void phase(unsigned step,pid_t pid) { notify_set_state(phaseToken,((uint64_t)step<<32)|(uint32_t)pid); }
static NSSet *installedIdentifiers(void) {
    NSMutableSet *ids=[NSMutableSet new];
    NSFileManager *fm=NSFileManager.defaultManager;
    for(NSString *root in @[@"/Applications",@"/var/jb/Applications",@"/var/containers/Bundle/Application"]) {
        NSDirectoryEnumerator *enumerator=[fm enumeratorAtURL:[NSURL fileURLWithPath:root] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL *url,NSError *error){ return YES; }];
        for(NSURL *url in enumerator) if([url.pathExtension isEqual:@"app"]) {
            NSString *bid=[NSDictionary dictionaryWithContentsOfFile:[url.path stringByAppendingPathComponent:@"Info.plist"]][@"CFBundleIdentifier"];
            if(bid) [ids addObject:bid]; [enumerator skipDescendants];
        }
    }
    return ids;
}
static uint64_t publish(NSString *name, uint64_t state) {
    NSNumber *n=tokens[name]; int t;
    if(!n) { if(notify_register_check(name.UTF8String,&t)) return 0; tokens[name]=@(t); }
    else t=n.intValue;
    notify_set_state(t,state); notify_post(name.UTF8String); return state;
}
static void reload(void) {
    preferences=SDReadPrefs();
    publish(@SD_GLOBAL, SDGlobalState(preferences));
    NSDictionary *apps=preferences[@"apps"];
    NSMutableSet *ids=[NSMutableSet setWithArray:apps.allKeys ?: @[]];
    for(NSString *key in tokens.allKeys) if([key hasPrefix:@"com.alsinas.sounddeck.gain."]) [ids addObject:[key substringFromIndex:@"com.alsinas.sounddeck.gain.".length]];
    for(NSString *bid in ids) publish(SDGainName(bid),SDConfig(preferences,apps[bid]));
    // Fixed destination and validated identifiers only. No shell, arbitrary paths or executable IPC.
    NSMutableArray *bundles=[NSMutableArray arrayWithArray:@[@"com.alsinas.sounddeck.toneA",@"com.alsinas.sounddeck.toneB"]];
    NSMutableSet *requested=[NSMutableSet new];
    for(NSString *bid in apps) if([apps[bid][@"enrolled"] boolValue]) [requested addObject:bid];
    if(![requested isEqual:lastEnrollment]) { knownInstalled=installedIdentifiers(); lastEnrollment=[requested copy]; }
    NSSet *installed=knownInstalled;
    NSCharacterSet *invalid=[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"] invertedSet];
    for(NSString *bid in apps) if([apps[bid][@"enrolled"] boolValue] && [installed containsObject:bid] && bid.length<256 && [bid rangeOfCharacterFromSet:invalid].location==NSNotFound && ![bundles containsObject:bid] && ![bid isEqual:@"com.alsinas.sounddeck"] && ![bid isEqual:@"com.apple.springboard"])
        [bundles addObject:bid];
    NSDictionary *filter=@{@"Filter":@{@"Bundles":bundles}};
    NSString *path=@"/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.plist";
    // Privilege is used only for the fixed, root-owned injection filter. All user-file I/O runs as mobile.
    if(![filter isEqual:[NSDictionary dictionaryWithContentsOfFile:path]]) {
        if(seteuid(0)==0) { [filter writeToFile:path atomically:YES]; chmod(path.fileSystemRepresentation,0644); seteuid(501); }
    }
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
    for(int i=0;i<MIN(actual,(int)pids.length/(int)sizeof(pid_t));i++) {
        pid_t pid=((pid_t *)pids.mutableBytes)[i]; if(pid<=0) continue;
        [livePIDs addObject:@(pid)];
        char path[PROC_PIDPATHINFO_MAXSIZE]={0};
        if(proc_pidpath(pid,path,sizeof(path))<=0) continue;
        NSString *exe=@(path);
        if(![exe hasPrefix:@"/Applications/"] && ![exe hasPrefix:@"/private/var/containers/Bundle/Application/"] && ![exe hasPrefix:@"/var/containers/Bundle/Application/"] && ![exe hasPrefix:rootlessApplications]) continue;
        phase(2,pid);
        NSRange r=[exe rangeOfString:@".app/"];
        if(r.location==NSNotFound) continue;
        phase(3,pid);
        int token=0; uint64_t state=0; NSNumber *cached=clientTokens[@(pid)];
        if(cached) token=cached.intValue;
        else if(!notify_register_check(SDClientName(pid).UTF8String,&token)) clientTokens[@(pid)]=@(token);
        if(clientTokens[@(pid)] && notify_get_state(token,&state)) { notify_cancel(token); [clientTokens removeObjectForKey:@(pid)]; state=0; }
        if(!SDFresh(state)) continue;
        NSString *bundle=[exe substringToIndex:r.location+4];
        phase(4,pid);
        NSDictionary *info=metadataCache[bundle];
        if(!info) { info=[NSDictionary dictionaryWithContentsOfFile:[bundle stringByAppendingPathComponent:@"Info.plist"]]; if(info) metadataCache[bundle]=info; }
        NSString *bid=info[@"CFBundleIdentifier"]; if(!bid) continue;
        NSDictionary *entry=preferences[@"apps"][bid];
        NSString *gainName=SDGainName(bid);
        uint64_t expected=SDConfig(preferences,entry);
        if(!tokens[gainName]) publish(gainName,expected);
        [clients addObject:@{@"bundleID":bid,@"name":info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: bid,
          @"pid":@(pid),@"active":@((state&1)!=0),@"path":SDPathName((state>>1)&7),
          @"gain":@(((state>>4)&1023)/1000.),@"inputRMS":@(((state>>14)&65535)/65535.),
          @"outputRMS":@(((state>>30)&65535)/65535.),@"metered":@(((state>>1)&7)==1)}];
    }
    for(NSNumber *pid in clientTokens.allKeys) if(![livePIDs containsObject:pid]) { notify_cancel(clientTokens[pid].intValue); [clientTokens removeObjectForKey:pid]; }
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
    rootlessApplications=[[@"/var/jb/Applications" stringByResolvingSymlinksInPath] stringByAppendingString:@"/"];
    if(getuid()==0) { setegid(501); if(seteuid(501)) return 1; }
    notify_register_check("com.alsinas.sounddeck.service-phase",&phaseToken);
    [[NSFileManager defaultManager] createDirectoryAtPath:SD_DIR withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    @autoreleasepool { reload(); }
    int t; notify_register_dispatch(SD_CHANGED,&t,dispatch_get_main_queue(),^(int token){ @autoreleasepool { reload(); snapshot(); } });
    serviceTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(serviceTimer,DISPATCH_TIME_NOW,NSEC_PER_SEC,200*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(serviceTimer,^{ @autoreleasepool { snapshot(); } }); dispatch_resume(serviceTimer);
    dispatch_main();
} }
