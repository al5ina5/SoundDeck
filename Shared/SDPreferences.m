#import "SDProtocol.h"
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
NSDictionary *SDSanitizePrefs(NSDictionary *input) {
    if(![input isKindOfClass:NSDictionary.class]) input=@{};
    NSMutableDictionary *out=[@{@"mixing":@YES,@"disabled":@NO,@"appearance":@0} mutableCopy];
    for(NSString *key in @[@"mixing",@"disabled"]) if([input[key] isKindOfClass:NSNumber.class]) out[key]=@([input[key] boolValue]);
    if([input[@"appearance"] isKindOfClass:NSNumber.class]) out[@"appearance"]=@(MAX(0,MIN(2,[input[@"appearance"] integerValue])));
    NSMutableDictionary *apps=[NSMutableDictionary new];
    NSDictionary *source=[input[@"apps"] isKindOfClass:NSDictionary.class]?input[@"apps"]:@{};
    NSCharacterSet *invalid=[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"] invertedSet];
    for(NSString *bid in source) {
        if(![bid isKindOfClass:NSString.class] || !bid.length || bid.length>255 || [bid rangeOfCharacterFromSet:invalid].location!=NSNotFound || ![source[bid] isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *a=source[bid]; NSMutableDictionary *entry=[NSMutableDictionary new];
        if([a[@"gain"] isKindOfClass:NSNumber.class]) { double value=[a[@"gain"] doubleValue]; entry[@"gain"]=@(isfinite(value)?fmax(0.,fmin(1.,value)):1.); }
        if([a[@"muted"] isKindOfClass:NSNumber.class]) entry[@"muted"]=@([a[@"muted"] boolValue]);
        if([a[@"name"] isKindOfClass:NSString.class] && [a[@"name"] length]<=512) entry[@"name"]=a[@"name"];
        apps[bid]=entry;
    }
    out[@"apps"]=apps; return out;
}
NSDictionary *SDReadPrefs(void) { return SDSanitizePrefs([NSDictionary dictionaryWithContentsOfFile:SD_PREFS]); }
static BOOL writePrefs(NSDictionary *prefs,NSDictionary *changes,NSError **error) {
    [[NSFileManager defaultManager] createDirectoryAtPath:SD_DIR withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error];
    int fd=open([SD_DIR @"/preferences.lock" fileSystemRepresentation],O_CREAT|O_RDWR,0600);
    if(fd<0) return NO;
    flock(fd,LOCK_EX);
    if(changes) {
        NSMutableDictionary *latest=[SDReadPrefs() mutableCopy];
        for(NSString *key in changes) {
            if([key isEqual:@"apps"]) {
                NSMutableDictionary *apps=[latest[@"apps"] mutableCopy];
                for(NSString *bid in changes[key]) {
                    NSMutableDictionary *entry=[apps[bid] mutableCopy] ?: [NSMutableDictionary new];
                    [entry addEntriesFromDictionary:changes[key][bid]]; apps[bid]=entry;
                }
                latest[key]=apps;
            } else latest[key]=changes[key];
        }
        prefs=latest;
    }
    prefs=SDSanitizePrefs(prefs);
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:prefs format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    BOOL ok=data && [data writeToFile:SD_PREFS options:NSDataWritingAtomic error:error];
    if(ok) chmod(SD_PREFS.fileSystemRepresentation,0600);
    flock(fd,LOCK_UN); close(fd);
    if(ok) notify_post(SD_CHANGED);
    return ok;
}
BOOL SDWritePrefs(NSDictionary *prefs,NSError **error) { return writePrefs(prefs,nil,error); }
BOOL SDUpdatePrefs(NSDictionary *changes,NSError **error) { return writePrefs(nil,changes,error); }
