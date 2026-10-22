#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <math.h>
#include <stdatomic.h>
#include <notify.h>
#include <unistd.h>
#ifndef SD_FREQUENCY
#define SD_FREQUENCY 440
#endif
static AudioUnit unit;
static double phase;
static _Atomic(unsigned) observedRMS,observedBuffers;
static OSStatus observe(void *ref,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *time,UInt32 bus,UInt32 frames,AudioBufferList *data) {
    if(!(*flags & kAudioUnitRenderAction_PostRender) || !data) return noErr;
    double sum=0; size_t count=0;
    for(UInt32 b=0;b<data->mNumberBuffers;b++) {
        if(!data->mBuffers[b].mData) continue;
        float *p=data->mBuffers[b].mData; size_t n=data->mBuffers[b].mDataByteSize/sizeof(float);
        for(size_t i=0;i<n;i++) sum+=(double)p[i]*p[i]; count+=n;
    }
    if(count) { atomic_store(&observedRMS,(unsigned)fmin(65535.,sqrt(sum/count)*65535.)); atomic_fetch_add(&observedBuffers,1); }
    return noErr;
}
static OSStatus tone(void *ref,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *time,UInt32 bus,UInt32 frames,AudioBufferList *data) {
    for(UInt32 i=0;i<frames;i++) {
        float value=0.08f*sinf(phase);
        phase+=2*M_PI*SD_FREQUENCY/48000.; if(phase>=2*M_PI) phase-=2*M_PI;
        for(UInt32 b=0;b<data->mNumberBuffers;b++) for(UInt32 c=0;c<data->mBuffers[b].mNumberChannels;c++)
            ((float *)data->mBuffers[b].mData)[i*data->mBuffers[b].mNumberChannels+c]=value;
    }
    return noErr;
}
@interface ToneDelegate:UIResponder<UIApplicationDelegate>
@property(strong,nonatomic) UIWindow *window;
@end
@implementation ToneDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *vc=[UIViewController new]; vc.view.backgroundColor=UIColor.systemBackgroundColor;
    UILabel *label=[UILabel new]; label.numberOfLines=0; label.textAlignment=NSTextAlignmentCenter;
    label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
    label.text=[NSString stringWithFormat:@"SoundDeck Test Signal\n%d Hz · −22 dBFS peak\n\nUses non-mixing AVAudioSession deliberately.\nSoundDeck must enable concurrent playback.",SD_FREQUENCY];
    label.translatesAutoresizingMaskIntoConstraints=NO; [vc.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.leadingAnchor constant:32],[label.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-32],[label.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor]]];
    self.window.rootViewController=vc; [self.window makeKeyAndVisible];
    AVAudioSession *session=AVAudioSession.sharedInstance; NSError *error=nil;
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    [session setPreferredSampleRate:48000 error:&error];
    [session setActive:YES withOptions:0 error:&error];
    AudioComponentDescription desc={kAudioUnitType_Output,kAudioUnitSubType_RemoteIO,kAudioUnitManufacturer_Apple,0,0};
    OSStatus status=AudioComponentInstanceNew(AudioComponentFindNext(NULL,&desc),&unit);
    AudioStreamBasicDescription fmt={48000,kAudioFormatLinearPCM,kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,4,1,4,1,32,0};
    status|=AudioUnitSetProperty(unit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&fmt,sizeof(fmt));
    AURenderCallbackStruct cb={tone,NULL};
    status|=AudioUnitSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&cb,sizeof(cb));
    status|=AudioUnitAddRenderNotify(unit,observe,NULL);
    status|=AudioUnitInitialize(unit); status|=AudioOutputUnitStart(unit);
    if(status || error) label.text=[NSString stringWithFormat:@"Audio initialization failed: %d %@",(int)status,error];
    int token; NSString *notifyName=[@"com.alsinas.sounddeck.test." stringByAppendingString:NSBundle.mainBundle.bundleIdentifier];
    notify_register_check(notifyName.UTF8String,&token);
    int sessionToken; NSString *sessionName=[@"com.alsinas.sounddeck.session." stringByAppendingString:NSBundle.mainBundle.bundleIdentifier];
    notify_register_check(sessionName.UTF8String,&sessionToken);
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){
        uint64_t value=((uint64_t)atomic_load(&observedBuffers)<<32)|atomic_load(&observedRMS); notify_set_state(token,value);
        notify_set_state(sessionToken,((uint64_t)(uint32_t)getpid()<<32)|(uint32_t)session.categoryOptions);
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:AVAudioSessionInterruptionNotification object:session queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
        if([n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue]==AVAudioSessionInterruptionTypeEnded) {
            [session setActive:YES withOptions:0 error:nil]; AudioOutputUnitStart(unit);
        }
    }];
    return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(ToneDelegate.class)); } }
