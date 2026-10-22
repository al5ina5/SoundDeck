#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <stdio.h>
#include <notify.h>
int main(int argc,char **argv) { @autoreleasepool {
    if(argc<3) { fprintf(stderr,"sd-device launch BUNDLE | state NOTIFY_NAME | post NOTIFY_NAME\n"); return 2; }
    if(!strcmp(argv[1],"state")) { int token; uint64_t s=0; if(notify_register_check(argv[2],&token)) return 1; notify_get_state(token,&s); notify_cancel(token); printf("%llu\n",s); return 0; }
    if(!strcmp(argv[1],"post")) { notify_post(argv[2]); return 0; }
    if(!strcmp(argv[1],"launch")) {
        dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",RTLD_NOW);
        Class cls=NSClassFromString(@"FBSOpenApplicationService");
        id service=((id(*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(@"serviceWithDefaultShellEndpoint"));
        NSString * __unsafe_unretained *key=(NSString * __unsafe_unretained *)dlsym(RTLD_DEFAULT,"FBSOpenApplicationOptionKeyUnlockDevice");
        id options=((id(*)(id,SEL,id))objc_msgSend)(NSClassFromString(@"FBSOpenApplicationOptions"),NSSelectorFromString(@"optionsWithDictionary:"),@{key?*key:@"__UnlockDevice":@YES});
        __block BOOL done=NO; __block int result=1;
        ((void(*)(id,SEL,id,id,id))objc_msgSend)(service,NSSelectorFromString(@"openApplication:withOptions:completion:"),@(argv[2]),options,^(id request,NSError *error){
            fprintf(stderr,"launch: %s\n",error?error.description.UTF8String:"OK"); result=error?1:0; done=YES;
        });
        NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:15];
        while(!done && limit.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        return done?result:3;
    }
    return 2;
} }
