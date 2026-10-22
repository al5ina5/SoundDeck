#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdatomic.h>
#include <stdint.h>
#include <notify.h>
#include <unistd.h>
#ifndef SD_MODE
#define SD_MODE 1
#endif
static const double kFrequency=SD_MODE==2?660:(SD_MODE==3?550:770);
#if SD_MODE==1 || SD_MODE==4 || SD_MODE==5
static double phase;
#endif
static _Atomic(unsigned) buffers;
static _Atomic(unsigned) observedRMS;
static NSString *bundleID;
#if SD_MODE==1
static AudioQueueRef queue;
#endif
#if SD_MODE==2
static AVPlayer *avPlayer;
#endif
#if SD_MODE==3
static AVAudioPlayer *audioPlayer;
#endif
#if SD_MODE==5
static AVSampleBufferAudioRenderer *sampleRenderer;
static AVSampleBufferRenderSynchronizer *sampleSynchronizer;
static CMAudioFormatDescriptionRef sampleFormat;
#endif
#if SD_MODE==2 || SD_MODE==3
static NSData *wavData(double freq,double seconds) {
    NSMutableData *d=[NSMutableData data]; uint16_t shortValue;
    #define APPEND(type,val) do { type v=(val); [d appendBytes:&v length:sizeof(v)]; } while(0)
    APPEND(uint32_t,0x46464952); APPEND(uint32_t,0); APPEND(uint32_t,0x45564157);
    APPEND(uint32_t,0x20746d66); APPEND(uint32_t,16); APPEND(uint16_t,1); APPEND(uint16_t,1);
    APPEND(uint32_t,44100); APPEND(uint32_t,88200); APPEND(uint16_t,2); APPEND(uint16_t,16);
    APPEND(uint32_t,0x61746164);
    NSUInteger frames=(NSUInteger)(44100*seconds);
    for(NSUInteger i=0;i<frames;i++) { shortValue=(uint16_t)(int16_t)lround(0.08*32767.*sin(2*M_PI*freq*i/44100.)); [d appendBytes:&shortValue length:2]; }
    uint32_t size=(uint32_t)(d.length-8), dataSize=(uint32_t)(d.length-44);
    [d replaceBytesInRange:NSMakeRange(4,4) withBytes:&size]; [d replaceBytesInRange:NSMakeRange(40,4) withBytes:&dataSize];
    #undef APPEND
    return d;
}
#endif
static int sessionToken=-1,meterToken=-1;
static void publishSession(void) {
    if(sessionToken<0) {
        notify_register_check([@"com.alsinas.sounddeck.session." stringByAppendingString:bundleID].UTF8String,&sessionToken);
        notify_register_check([@"com.alsinas.sounddeck.test." stringByAppendingString:bundleID].UTF8String,&meterToken);
    }
    if(sessionToken>=0) notify_set_state(sessionToken,((uint64_t)(uint32_t)getpid()<<32)|(uint32_t)AVAudioSession.sharedInstance.categoryOptions);
    if(meterToken>=0) notify_set_state(meterToken,((uint64_t)atomic_load(&buffers)<<32)|atomic_load(&observedRMS));
}
#if SD_MODE==4
static OSStatus observe(void *ref,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *time,UInt32 bus,UInt32 frames,AudioBufferList *data) {
    if(!(*flags&kAudioUnitRenderAction_PostRender) || !data) return noErr;
    double sum=0; size_t count=0;
    for(UInt32 b=0;b<data->mNumberBuffers;b++) { float *p=data->mBuffers[b].mData; size_t n=data->mBuffers[b].mDataByteSize/sizeof(float); for(size_t i=0;i<n;i++) { sum+=(double)p[i]*p[i]; count++; } }
    if(count) { atomic_store(&observedRMS,(unsigned)fmin(65535.,sqrt(sum/count)*65535.)); atomic_fetch_add(&buffers,1); }
    return noErr;
}
#endif
#if SD_MODE==1
static void queueTone(void *ref,AudioQueueRef q,AudioQueueBufferRef buffer) {
    float *p=buffer->mAudioData; size_t n=buffer->mAudioDataBytesCapacity/sizeof(float);
    for(size_t i=0;i<n;i++) { p[i]=0.08f*sinf(phase); phase+=2*M_PI*kFrequency/48000.; if(phase>=2*M_PI) phase-=2*M_PI; }
    atomic_fetch_add(&buffers,1); atomic_store(&observedRMS,(unsigned)(0.08/sqrt(2.)*65535.));
    AudioQueueEnqueueBuffer(q,buffer,0,NULL);
}
#endif
static void setBase(double base) {
#if SD_MODE==1
    if(queue) AudioQueueSetParameter(queue,kAudioQueueParam_Volume,base);
#elif SD_MODE==2
    avPlayer.volume=base;
#elif SD_MODE==3
    audioPlayer.volume=base;
#elif SD_MODE==5
    sampleRenderer.volume=base;
#else
    // Engine output is attenuated by SoundDeck's PCM path; this is the fixture's own mixer trim.
    // A source-node player has no public volume, so report unity as its base.
#endif
}
@interface MediaDelegate:UIResponder<UIApplicationDelegate>
@property(strong,nonatomic) UIWindow *window;
@property(strong,nonatomic) AVAudioEngine *engine;
@end
@implementation MediaDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    bundleID=NSBundle.mainBundle.bundleIdentifier;
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *vc=[UIViewController new]; vc.view.backgroundColor=UIColor.systemBackgroundColor;
    UILabel *label=[UILabel new]; label.numberOfLines=0; label.textAlignment=NSTextAlignmentCenter; label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    NSString *kind=@[@"",@"AudioQueue",@"AVPlayer",@"AVAudioPlayer",@"AVAudioEngine",@"Sample buffer"][SD_MODE];
    label.text=[NSString stringWithFormat:@"SoundDeck audio adapter fixture\n%@\n%.0f Hz · base volume 0.9",kind,kFrequency];
    label.translatesAutoresizingMaskIntoConstraints=NO; [vc.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.leadingAnchor constant:32],[label.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-32],[label.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor]]];
    self.window.rootViewController=vc; [self.window makeKeyAndVisible];
    AVAudioSession *session=AVAudioSession.sharedInstance; NSError *error=nil;
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    [session setPreferredSampleRate:48000 error:&error]; [session setActive:YES withOptions:0 error:&error];
#if SD_MODE==1
    AudioStreamBasicDescription fmt={48000,kAudioFormatLinearPCM,kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,4,1,4,1,32,0};
    OSStatus status=AudioQueueNewOutput(&fmt,queueTone,NULL,NULL,NULL,0,&queue);
    if(!status) for(int i=0;i<3;i++) { AudioQueueBufferRef buffer; status=AudioQueueAllocateBuffer(queue,4800,&buffer); if(!status) queueTone(NULL,queue,buffer); }
    if(!status) { AudioQueueSetParameter(queue,kAudioQueueParam_Volume,0.9); status=AudioQueueStart(queue,NULL); }
    if(status) label.text=[NSString stringWithFormat:@"AudioQueue failed: %d",(int)status];
#elif SD_MODE==2
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"sounddeck-avp.wav"];
    [wavData(kFrequency,2) writeToFile:path atomically:YES];
    avPlayer=[AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
    avPlayer.volume=0.9; avPlayer.actionAtItemEnd=AVPlayerActionAtItemEndNone;
    [NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:avPlayer.currentItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ [avPlayer seekToTime:kCMTimeZero]; [avPlayer play]; }];
    [avPlayer play];
#elif SD_MODE==3
    audioPlayer=[[AVAudioPlayer alloc] initWithData:wavData(kFrequency,2) error:&error];
    audioPlayer.numberOfLoops=-1; audioPlayer.volume=0.9; [audioPlayer play];
    if(error) label.text=[NSString stringWithFormat:@"AVAudioPlayer failed: %@",error.localizedDescription];
#elif SD_MODE==4
    self.engine=[AVAudioEngine new];
    AVAudioFormat *format=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
    AVAudioSourceNode *source=[[AVAudioSourceNode alloc] initWithRenderBlock:^OSStatus(BOOL *silence,const AudioTimeStamp *timestamp,AVAudioFrameCount frameCount,AudioBufferList *data){
        for(UInt32 b=0;b<data->mNumberBuffers;b++) { float *p=data->mBuffers[b].mData; for(UInt32 i=0;i<frameCount;i++) { p[i]=0.08f*sinf(phase); phase+=2*M_PI*kFrequency/48000.; if(phase>=2*M_PI) phase-=2*M_PI; } }
        atomic_fetch_add(&buffers,1); return noErr;
    }];
    [self.engine attachNode:source]; [self.engine connect:source to:self.engine.mainMixerNode format:format];
    self.engine.mainMixerNode.outputVolume=1;
    if(![self.engine startAndReturnError:&error]) label.text=[NSString stringWithFormat:@"AVAudioEngine failed: %@",error.localizedDescription];
    AudioUnit output=self.engine.outputNode.audioUnit;
    if(output) AudioUnitAddRenderNotify(output,observe,NULL);
#else
    AudioStreamBasicDescription asbd={48000,kAudioFormatLinearPCM,kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,8,1,8,2,32,0};
    CMAudioFormatDescriptionCreate(kCFAllocatorDefault,&asbd,0,NULL,0,NULL,NULL,&sampleFormat);
    sampleRenderer=[AVSampleBufferAudioRenderer new];
    sampleRenderer.volume=0.9;
    sampleSynchronizer=[AVSampleBufferRenderSynchronizer new]; [sampleSynchronizer addRenderer:sampleRenderer];
    sampleSynchronizer.rate=1;
    __block double sampleTime=0; __block OSStatus sampleStatus=0;
    NSTimer *feed=[NSTimer scheduledTimerWithTimeInterval:.25 repeats:YES block:^(NSTimer *t){
        if(!sampleRenderer.readyForMoreMediaData && sampleTime>0) return;
        UInt32 frames=12000; size_t bytes=(size_t)frames*2*sizeof(float); float *pcm=calloc(bytes,1);
        for(UInt32 i=0;i<frames;i++) { float value=0.08f*sinf(phase); phase+=2*M_PI*kFrequency/48000.; if(phase>=2*M_PI) phase-=2*M_PI; pcm[i*2]=value; pcm[i*2+1]=value; }
        CMBlockBufferRef block=NULL; if(CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,pcm,bytes,kCFAllocatorMalloc,NULL,0,bytes,0,&block)) { free(pcm); return; }
        CMSampleBufferRef sample=NULL; CMSampleTimingInfo timing={CMTimeMake(1,48000),CMTimeMakeWithSeconds(sampleTime,48000),kCMTimeInvalid};
        sampleStatus=CMSampleBufferCreateReady(kCFAllocatorDefault,block,sampleFormat,frames,1,&timing,0,NULL,&sample);
        if(!sampleStatus) {
            [sampleRenderer enqueueSampleBuffer:sample]; CFRelease(sample); atomic_fetch_add(&buffers,1); atomic_store(&observedRMS,(unsigned)(0.08/sqrt(2.)*65535.)); sampleTime+=frames/48000.;
        }
        CFRelease(block);
    }];
    (void)feed;
#endif
    publishSession();
    NSTimer *timer=[NSTimer scheduledTimerWithTimeInterval:.5 repeats:YES block:^(NSTimer *t){
        #if SD_MODE==2
        if(avPlayer.timeControlStatus==AVPlayerTimeControlStatusPlaying) { atomic_fetch_add(&buffers,1); atomic_store(&observedRMS,(unsigned)(0.08/sqrt(2.)*65535.)); }
        #elif SD_MODE==3
        if(audioPlayer.isPlaying) { atomic_fetch_add(&buffers,1); atomic_store(&observedRMS,(unsigned)(0.08/sqrt(2.)*65535.)); }
        #elif SD_MODE==5
        if(sampleSynchronizer.rate!=0) { atomic_fetch_add(&buffers,1); atomic_store(&observedRMS,(unsigned)(0.08/sqrt(2.)*65535.)); }
        #endif
        publishSession();
    }];
    (void)timer;
    // Test hook: change the app's own volume while SoundDeck is controlling it.
    int baseToken; notify_register_dispatch([@"com.alsinas.sounddeck.test-base." stringByAppendingString:bundleID].UTF8String,&baseToken,dispatch_get_main_queue(),^(int token){ setBase(0.6); });
    return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(MediaDelegate.class)); } }
