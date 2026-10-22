#import "../Shared/SDProtocol.h"
#import "SDControlCenterConfig.h"
#include <stdio.h>
#include <unistd.h>
static int usage(void) { fprintf(stderr,"sdctl status | gain BUNDLE 0..100 | mute BUNDLE 0|1 | mixing 0|1 | appearance 0|1|2 | capture | cc-show | cc-expand | cc-capture | cc-dismiss | cc-status | disable | enable | reset\n"); return 2; }
int main(int argc,char **argv) { @autoreleasepool {
    if(argc<2) return usage(); NSString *command=@(argv[1]);
    if([command isEqual:@"enroll"]) { puts("Enrollment is no longer necessary. Audio apps are discovered automatically."); return 0; }
    if([@[@"cc-show",@"cc-expand",@"cc-capture",@"cc-dismiss"] containsObject:command]) { notify_post([[@"com.alsinas.sounddeck.cc." stringByAppendingString:[command substringFromIndex:3]] UTF8String]); return 0; }
    if([command isEqual:@"cc-install"] || [command isEqual:@"cc-remove"]) { NSError *error=nil; BOOL ok=SDConfigureControlCenter([command isEqual:@"cc-install"],&error); if(!ok) fprintf(stderr,"Control Center configuration not changed: %s\n",error?error.description.UTF8String:"no existing CCSupport layout found; add SoundDeck in Settings > Control Center"); return ok?0:1; }
    if([command isEqual:@"is-disabled"]) return [SDReadPrefs()[@"disabled"] boolValue]?0:1;
    if([command isEqual:@"capture"]) { notify_post("com.alsinas.sounddeck.capture"); return 0; }
    if([command isEqual:@"status"] || [command isEqual:@"cc-status"]) {
        NSDictionary *status=[NSDictionary dictionaryWithContentsOfFile:[command isEqual:@"cc-status"]?SD_DIR @"/cc-diagnostics.plist":SD_STATUS] ?: @{};
        NSData *json=[NSJSONSerialization dataWithJSONObject:status options:NSJSONWritingPrettyPrinted error:nil];
        if(json) fwrite(json.bytes,1,json.length,stdout); puts(""); return status.count?0:1;
    }
    NSDictionary *original=SDReadPrefs();
    NSMutableDictionary *p=[original mutableCopy];
    NSMutableDictionary *apps=[p[@"apps"] mutableCopy] ?: [NSMutableDictionary new];
    if([@[@"gain",@"mute"] containsObject:command]) {
        if(argc<3) return usage(); NSString *bid=@(argv[2]);
        NSMutableDictionary *a=[apps[bid] mutableCopy] ?: [NSMutableDictionary new];
        { if(argc!=4) return usage(); char *end=NULL; double value=strtod(argv[3],&end);
            if(*end || !isfinite(value) || value<0 || value>([command isEqual:@"gain"]?100:1)) return usage();
            a[[command isEqual:@"gain"]?@"gain":@"muted"]=[command isEqual:@"gain"]?@(value/100.):@(value!=0);
        }
        apps[bid]=a; p[@"apps"]=apps;
    } else if([command isEqual:@"mixing"]) { if(argc!=3) return usage(); p[@"mixing"]=@(atoi(argv[2])!=0); }
    else if([command isEqual:@"appearance"]) { if(argc!=3 || atoi(argv[2])<0 || atoi(argv[2])>2) return usage(); p[@"appearance"]=@(atoi(argv[2])); }
    else if([command isEqual:@"disable"]) p[@"disabled"]=@YES;
    else if([command isEqual:@"enable"]) p[@"disabled"]=@NO;
    else if([command isEqual:@"reset"]) p=[@{@"mixing":@YES,@"apps":@{}} mutableCopy];
    else return usage();
    if(getuid()==0) { fprintf(stderr,"Run sdctl as mobile, not root (preferences are owned by mobile).\n"); return 2; }
    NSMutableDictionary *changes=[NSMutableDictionary new];
    for(NSString *key in p) {
        if([key isEqual:@"apps"]) {
            NSMutableDictionary *deltaApps=[NSMutableDictionary new];
            for(NSString *bid in p[key]) {
                NSMutableDictionary *fields=[NSMutableDictionary new];
                for(NSString *field in p[key][bid]) if(![p[key][bid][field] isEqual:original[key][bid][field]]) fields[field]=p[key][bid][field];
                if(fields.count) deltaApps[bid]=fields;
            }
            if(deltaApps.count) changes[key]=deltaApps;
        } else if(![p[key] isEqual:original[key]]) changes[key]=p[key];
    }
    NSError *error=nil;
    BOOL success=[command isEqual:@"reset"]?SDWritePrefs(p,&error):SDUpdatePrefs(changes,&error);
    if(!success) { fprintf(stderr,"%s\n",error.description.UTF8String); return 1; } return 0;
} }
