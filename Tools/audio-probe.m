#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>
int main(int argc,char **argv) { @autoreleasepool {
    dlopen("/System/Library/PrivateFrameworks/Celestial.framework/Celestial",RTLD_NOW);
    dlopen("/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer",RTLD_NOW);
    if(argc>1) {
        Class cls=NSClassFromString(@"AVSystemController");
        id controller=((id(*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(@"sharedAVSystemController"));
        SEL get=NSSelectorFromString(@"getVolume:forCategory:"),set=NSSelectorFromString(@"setVolumeTo:forCategory:");
        float initial=-1,changed=-1,restored=-1;
        BOOL read=((BOOL(*)(id,SEL,float *,id))objc_msgSend)(controller,get,&initial,@"Audio/Video");
        if(!read || initial<=0 || initial>1) { fprintf(stderr,"No reversible nonzero media volume available\n"); return 2; }
        BOOL wrote=((BOOL(*)(id,SEL,float,id))objc_msgSend)(controller,set,initial*.5f,@"Audio/Video");
        sleep(1); ((BOOL(*)(id,SEL,float *,id))objc_msgSend)(controller,get,&changed,@"Audio/Video");
        ((BOOL(*)(id,SEL,float,id))objc_msgSend)(controller,set,initial,@"Audio/Video");
        sleep(1); ((BOOL(*)(id,SEL,float *,id))objc_msgSend)(controller,get,&restored,@"Audio/Video");
        printf("read=%d wrote=%d initial=%f changed=%f restored=%f\n",read,wrote,initial,changed,restored);
        return read && wrote && changed<initial && fabs(restored-initial)<.01?0:1;
    }
    for(NSString *name in @[@"AVSystemController",@"MPVolumeSlider",@"MPVolumeView",@"MPVolumeController"]) {
        Class cls=NSClassFromString(name); unsigned count=0; Method *methods=class_copyMethodList(cls,&count);
        printf("%s\n",name.UTF8String);
        for(unsigned i=0;i<count;i++) { NSString *selector=NSStringFromSelector(method_getName(methods[i]));
            if([selector rangeOfString:@"volume" options:NSCaseInsensitiveSearch].location!=NSNotFound || [selector containsString:@"track"])
                printf("%s %s\n",selector.UTF8String,method_getTypeEncoding(methods[i]));
        } free(methods);
    }
    return 0;
} }
