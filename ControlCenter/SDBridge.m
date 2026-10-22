#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "../Shared/SDProtocol.h"
// UI-only SpringBoard bridge. It never installs audio hooks or creates a replacement Control Center.
__attribute__((constructor)) static void registerSoundDeckControlCenter(void) { @autoreleasepool {
    if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) return;
    int token,dismissToken;
    notify_register_dispatch("com.alsinas.sounddeck.cc.dismiss",&dismissToken,dispatch_get_main_queue(),^(int t){
        Class cls=NSClassFromString(@"SBControlCenterController"); SEL shared=NSSelectorFromString(@"sharedInstance");
        id controller=[cls respondsToSelector:shared]?((id(*)(id,SEL))objc_msgSend)(cls,shared):nil;
        __block BOOL requested=NO;
        for(NSString *name in @[@"dismissAnimated:",@"dismissAnimated:completion:",@"dismissControlCenterAnimated:"]) {
            SEL selector=NSSelectorFromString(name); NSMethodSignature *sig=[controller methodSignatureForSelector:selector];
            if(!sig || (sig.numberOfArguments!=3 && sig.numberOfArguments!=4)) continue;
            const char *type=[sig getArgumentTypeAtIndex:2]; if(strcmp(type,@encode(BOOL)) && strcmp(type,"c")) continue;
            if(sig.numberOfArguments==3) ((void(*)(id,SEL,BOOL))objc_msgSend)(controller,selector,YES);
            else ((void(*)(id,SEL,BOOL,id))objc_msgSend)(controller,selector,YES,nil);
            requested=YES;
            break;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            BOOL presented=[controller respondsToSelector:NSSelectorFromString(@"isPresented")] && ((BOOL(*)(id,SEL))objc_msgSend)(controller,NSSelectorFromString(@"isPresented"));
            [@{@"host":NSBundle.mainBundle.bundleIdentifier ?: @"",@"dismissRequested":@(requested),@"presentedAfter":@(presented)} writeToFile:SD_DIR @"/cc-bridge.plist" atomically:YES];
        });
    });
    notify_register_dispatch("com.alsinas.sounddeck.cc.show",&token,dispatch_get_main_queue(),^(int t){
        Class cls=NSClassFromString(@"SBControlCenterController"); SEL shared=NSSelectorFromString(@"sharedInstance");
        id controller=[cls respondsToSelector:shared]?((id(*)(id,SEL))objc_msgSend)(cls,shared):nil;
        BOOL requested=NO;
        for(NSString *name in @[@"presentAnimated:",@"presentAnimated:completion:"]) {
            SEL selector=NSSelectorFromString(name); NSMethodSignature *sig=[controller methodSignatureForSelector:selector];
            if(!sig || (sig.numberOfArguments!=3 && sig.numberOfArguments!=4)) continue;
            const char *type=[sig getArgumentTypeAtIndex:2]; if(strcmp(type,@encode(BOOL)) && strcmp(type,"c")) continue;
            if(sig.numberOfArguments==3) ((void(*)(id,SEL,BOOL))objc_msgSend)(controller,selector,YES);
            else ((void(*)(id,SEL,BOOL,id))objc_msgSend)(controller,selector,YES,nil);
            requested=YES; break;
        }
        NSMutableArray *selectors=[NSMutableArray new]; unsigned count=0; Method *methods=class_copyMethodList(cls,&count);
        for(unsigned i=0;i<count;i++) { NSString *name=NSStringFromSelector(method_getName(methods[i])); if([name containsString:@"present"] || [name containsString:@"Present"]) [selectors addObject:name]; } free(methods);
        [@{@"host":NSBundle.mainBundle.bundleIdentifier,@"requested":@(requested),@"selectors":selectors} writeToFile:SD_DIR @"/cc-bridge.plist" atomically:YES];
    });
} }
