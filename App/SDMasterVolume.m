#import "SDMasterVolume.h"
#import <objc/message.h>
#include <dlfcn.h>
#include <math.h>
@implementation SDMasterVolume
+ (id)controller {
    static id controller; static dispatch_once_t once;
    dispatch_once(&once,^{
        dlopen("/System/Library/PrivateFrameworks/Celestial.framework/Celestial",RTLD_LAZY);
        Class cls=NSClassFromString(@"AVSystemController"); SEL shared=NSSelectorFromString(@"sharedAVSystemController");
        if([cls respondsToSelector:shared]) controller=((id(*)(id,SEL))objc_msgSend)(cls,shared);
    }); return controller;
}
+ (BOOL)available {
    id c=[self controller]; return [c respondsToSelector:NSSelectorFromString(@"getVolume:forCategory:")] && [c respondsToSelector:NSSelectorFromString(@"setVolumeTo:forCategory:")];
}
+ (float)level {
    float value=-1;
    if([self available] && ((BOOL(*)(id,SEL,float *,id))objc_msgSend)([self controller],NSSelectorFromString(@"getVolume:forCategory:"),&value,@"Audio/Video")) return value;
    return -1;
}
+ (BOOL)setLevel:(float)level {
    if(![self available] || !isfinite(level)) return NO;
    // Media output only: never changes the ringer, alerts, recording gain or audio route.
    return ((BOOL(*)(id,SEL,float,id))objc_msgSend)([self controller],NSSelectorFromString(@"setVolumeTo:forCategory:"),fmaxf(0,fminf(1,level)),@"Audio/Video");
}
@end
