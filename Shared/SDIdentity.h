#pragma once
#import <Foundation/Foundation.h>
#include <unistd.h>
#include <dlfcn.h>
typedef struct { uint64_t ids[2]; uint64_t reserved[3]; } SDProcessCoalitions;
#ifdef __cplusplus
extern "C" int proc_pidinfo(int,int,uint64_t,void *,int);
#else
extern int proc_pidinfo(int,int,uint64_t,void *,int);
#endif
static inline NSString *SDCoalitionKey(pid_t pid) {
#ifdef __cplusplus
    SDProcessCoalitions c{};
#else
    SDProcessCoalitions c={0};
#endif
    if(proc_pidinfo(pid,20,0,&c,sizeof(c))!=sizeof(c) || !c.ids[0] || !c.ids[1]) return nil;
    return [NSString stringWithFormat:@"%llu/%llu",c.ids[0],c.ids[1]];
}
static inline BOOL SDExcludedBundle(NSString *bid) {
    return !bid || [@[@"com.alsinas.sounddeck",@"com.apple.springboard",@"com.apple.Preferences",@"com.apple.InCallService",@"com.apple.mobilephone",@"com.apple.facetime",@"com.apple.AssistantServices",@"com.apple.SiriViewService",@"com.apple.PassbookUIService",@"com.apple.AuthKitUIService"] containsObject:bid];
}
static inline pid_t SDResponsiblePID(pid_t pid) {
    typedef pid_t (*Resolve)(pid_t);
    static Resolve resolve; static dispatch_once_t once;
    dispatch_once(&once,^{ resolve=(Resolve)dlsym(RTLD_DEFAULT,"responsibility_get_pid_responsible_for_pid"); });
    return resolve?resolve(pid):-1;
}
