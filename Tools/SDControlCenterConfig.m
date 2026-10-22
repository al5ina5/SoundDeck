#import "SDControlCenterConfig.h"
#import "../Shared/SDProtocol.h"
#include <unistd.h>
BOOL SDConfigureControlCenter(BOOL install,NSError **error) {
    if(getuid()!=501) return NO;
    NSString *module=@"com.alsinas.sounddeck.cc",*marker=SD_DIR @"/cc-installed.plist";
    if(install && [NSFileManager.defaultManager fileExistsAtPath:marker]) return YES; // Respect later user removal/reordering.
    NSArray *paths=@[@"/var/jb/var/mobile/Library/ControlCenter/ModuleConfiguration_CCSupport.plist",@"/var/mobile/Library/ControlCenter/ModuleConfiguration_CCSupport.plist"];
    BOOL changed=NO;
    for(NSString *path in paths) {
        NSMutableDictionary *config=[[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy];
        if(![config[@"module-identifiers"] isKindOfClass:NSArray.class]) continue;
        NSMutableArray *ids=[config[@"module-identifiers"] mutableCopy];
        if(install) {
            if(![NSFileManager.defaultManager fileExistsAtPath:SD_DIR @"/cc-layout-backup.plist"])
                [config writeToFile:SD_DIR @"/cc-layout-backup.plist" atomically:YES];
            if(![ids containsObject:module]) [ids addObject:module];
        } else [ids removeObject:module];
        config[@"module-identifiers"]=ids;
        if([config[@"disabled-module-identifiers"] isKindOfClass:NSArray.class]) { NSMutableArray *disabled=[config[@"disabled-module-identifiers"] mutableCopy]; [disabled removeObject:module]; config[@"disabled-module-identifiers"]=disabled; }
        NSData *data=[NSPropertyListSerialization dataWithPropertyList:config format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
        if(!data || ![data writeToFile:path options:NSDataWritingAtomic error:error]) return NO;
        changed=YES; if(install) break; // Rootless active configuration takes precedence; never reset another layout.
    }
    if(install && changed) [@{@"module":module,@"version":SD_VERSION} writeToFile:marker atomically:YES];
    if(!install) [NSFileManager.defaultManager removeItemAtPath:marker error:nil];
    notify_post("com.opa334.ccsupport/ReloadProviders"); return changed;
}
