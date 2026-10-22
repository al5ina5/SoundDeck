#import "../Shared/SDProtocol.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>
#include <atomic>
#include <cmath>
#include <dlfcn.h>
#include <mach/mach_time.h>
#include <unistd.h>
#include <mutex>
extern "C" void MSHookFunction(void *,void *,void **);
extern "C" void MSHookMessageEx(Class,SEL,IMP,IMP *);
static std::atomic<float> gain{1.f};
static std::atomic<bool> enabled{true},mixing{true};
static std::atomic<uint64_t> frames{0};
static std::atomic<unsigned> inputRMS{0},outputRMS{0},backend{0};
static int configToken,globalToken,clientToken;
static NSString *bundleID;
static dispatch_source_t heartbeat;
// Fixed, process-lifetime contexts. Disposal retires rather than frees them: no callback UAF.
// Exhaustion fails open, leaving new units unchanged. Only RemoteIO playback bus 0 is intercepted.
struct Unit {
    AudioUnit unit=nullptr;
    AURenderCallback callback=nullptr;
    void *refcon=nullptr;
    std::atomic<unsigned> kind{0}; // immutable PCM layout published atomically: 1=f32, 2=s16, 3=s32
    std::atomic<unsigned> rampSamples{240};
    float currentGain=1.f; // render-thread owned; 5ms gain ramps avoid step discontinuities
};
static Unit units[128];
static unsigned unitCount=0;
static std::recursive_mutex controlMutex;
static OSStatus (*originalSetProperty)(AudioUnit,AudioUnitPropertyID,AudioUnitScope,AudioUnitElement,const void *,UInt32);
static OSStatus (*originalDispose)(AudioComponentInstance);
static OSStatus (*originalInitialize)(AudioUnit);
static void refreshFormat(Unit *u) {
    u->kind.store(0,std::memory_order_release);
    UInt32 size=sizeof(AudioStreamBasicDescription);
    AudioStreamBasicDescription fmt{};
    if(AudioUnitGetProperty(u->unit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&fmt,&size)) return;
    bool valid=fmt.mFormatID==kAudioFormatLinearPCM && !(fmt.mFormatFlags & kAudioFormatFlagIsBigEndian) &&
      (fmt.mFormatFlags & kAudioFormatFlagIsPacked) &&
      (((fmt.mFormatFlags & kAudioFormatFlagIsFloat) && fmt.mBitsPerChannel==32) ||
       ((fmt.mFormatFlags & kAudioFormatFlagIsSignedInteger) && (fmt.mBitsPerChannel==16 || fmt.mBitsPerChannel==32)));
    if(valid) { u->rampSamples.store(MAX(1,(unsigned)(fmt.mSampleRate*.005))); u->kind.store((fmt.mFormatFlags&kAudioFormatFlagIsFloat)?1:(fmt.mBitsPerChannel==16?2:3),std::memory_order_release); }
}
static OSStatus render(void *context,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *time,UInt32 bus,UInt32 n,AudioBufferList *data) {
    Unit *u=(Unit *)context;
    OSStatus result=u->callback(u->refcon,flags,time,bus,n,data);
    unsigned kind=u->kind.load(std::memory_order_acquire);
    if(result || !data || !kind) return result;
    float g=enabled.load(std::memory_order_relaxed)?gain.load(std::memory_order_relaxed):1.f;
    float initial=u->currentGain,delta=g-initial;
    float ramp=(float)u->rampSamples.load(std::memory_order_relaxed);
    double before=0,after=0; size_t samples=0;
    for(UInt32 b=0;b<data->mNumberBuffers;b++) {
        AudioBuffer &buffer=data->mBuffers[b]; if(!buffer.mData) continue;
        size_t count=buffer.mDataByteSize/(kind==2?2:4);
        unsigned channels=MAX(1,buffer.mNumberChannels);
        auto sampleGain=[&](size_t i) { return delta==0?g:initial+delta*fminf(1.f,(float)(i/channels+1)/ramp); };
        samples+=count;
        if(kind==1) {
            float *p=(float *)buffer.mData;
            for(size_t i=0;i<count;i++) { float x=p[i]; before+=(double)x*x; p[i]=x*sampleGain(i); after+=(double)p[i]*p[i]; }
        } else if(kind==2) {
            int16_t *p=(int16_t *)buffer.mData;
            for(size_t i=0;i<count;i++) { double x=p[i]/32768.; before+=x*x; p[i]=(int16_t)(p[i]*sampleGain(i)); double y=p[i]/32768.; after+=y*y; }
        } else {
            int32_t *p=(int32_t *)buffer.mData;
            for(size_t i=0;i<count;i++) { double x=p[i]/2147483648.; before+=x*x; p[i]=(int32_t)(p[i]*(double)sampleGain(i)); double y=p[i]/2147483648.; after+=y*y; }
        }
    }
    u->currentGain=initial+delta*fminf(1.f,n/ramp);
    if(samples) {
        inputRMS.store((unsigned)fmin(65535.,sqrt(before/samples)*65535.),std::memory_order_relaxed);
        outputRMS.store((unsigned)fmin(65535.,sqrt(after/samples)*65535.),std::memory_order_relaxed);
        frames.fetch_add(n,std::memory_order_relaxed);
    }
    return result;
}
static Unit *findUnit(AudioUnit unit) { for(unsigned i=0;i<unitCount;i++) if(units[i].unit==unit) return &units[i]; return nullptr; }
static bool isOutput(AudioUnit unit) {
    AudioComponentDescription d{};
    return !AudioComponentGetDescription(AudioComponentInstanceGetComponent(unit),&d) &&
      d.componentType==kAudioUnitType_Output && d.componentSubType==kAudioUnitSubType_RemoteIO;
}
static OSStatus setProperty(AudioUnit unit,AudioUnitPropertyID prop,AudioUnitScope scope,AudioUnitElement element,const void *data,UInt32 size) {
    std::lock_guard<std::recursive_mutex> lock(controlMutex);
    if(prop==kAudioUnitProperty_SetRenderCallback && element==0 && data && size==sizeof(AURenderCallbackStruct) &&
       (scope==kAudioUnitScope_Input || scope==kAudioUnitScope_Global) && isOutput(unit)) {
        const auto *cb=(const AURenderCallbackStruct *)data;
        if(cb->inputProc==render || !cb->inputProc) return originalSetProperty(unit,prop,scope,element,data,size);
        Unit *u=findUnit(unit);
        // Property changes while rendering are not supported by Core Audio. Hosts must stop before reconfiguration.
        if(!u && unitCount<128) { u=&units[unitCount++]; u->unit=unit; }
        if(u) {
            u->callback=cb->inputProc; u->refcon=cb->inputProcRefCon;
            refreshFormat(u);
            AURenderCallbackStruct replacement={render,u};
            OSStatus result=originalSetProperty(unit,prop,scope,element,&replacement,sizeof(replacement));
            if(!result) backend.store(u->kind.load()?1:6); return result;
        }
    }
    OSStatus result=originalSetProperty(unit,prop,scope,element,data,size);
    if(!result && prop==kAudioUnitProperty_StreamFormat) { Unit *u=findUnit(unit); if(u) { refreshFormat(u); backend.store(u->kind.load()?1:6); } }
    return result;
}
static OSStatus initialize(AudioUnit unit) { std::lock_guard<std::recursive_mutex> lock(controlMutex); Unit *u=findUnit(unit); if(u) refreshFormat(u); return originalInitialize(unit); }
static OSStatus dispose(AudioComponentInstance unit) {
    std::lock_guard<std::recursive_mutex> lock(controlMutex);
    OSStatus status=originalDispose(unit);
    if(!status) { Unit *u=findUnit(unit); if(u) { u->kind.store(0); u->unit=nullptr; } }
    return status;
}
// Object-native gain path. Preserve each object's requested gain, never replace it with a global gain.
static NSHashTable *players;
static const void *baseKey=&baseKey;
static void (*playerVolume)(id,SEL,float);
static float (*playerGetVolume)(id,SEL);
static void (*playerRate)(id,SEL,float);
static BOOL (*sessionActive)(id,SEL,BOOL,AVAudioSessionSetActiveOptions,NSError **);
static void update(void);
static NSString *originalCategory,*originalMode;
static AVAudioSessionCategoryOptions originalOptions;
static bool sessionIsActive=false;
static float effective(void) { return enabled.load()?gain.load():1.f; }
static void setPlayerVolume(id self,SEL cmd,float v) {
    @synchronized(players) { [players addObject:self]; objc_setAssociatedObject(self,baseKey,@(v),OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    playerVolume(self,cmd,v*(backend.load()==1?1.f:effective()));
}
static float getPlayerVolume(id self,SEL cmd) { NSNumber *v=objc_getAssociatedObject(self,baseKey); return v?v.floatValue:playerGetVolume(self,cmd); }
static void setPlayerRate(id self,SEL cmd,float rate) {
    @synchronized(players) {
        [players addObject:self];
        if(!objc_getAssociatedObject(self,baseKey)) objc_setAssociatedObject(self,baseKey,@(playerGetVolume(self,@selector(volume))),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        float base=[objc_getAssociatedObject(self,baseKey) floatValue];
        playerVolume(self,@selector(setVolume:),base*(backend.load()==1?1.f:effective()));
    }
    if(backend.load()!=1) backend.store(3);
    playerRate(self,cmd,rate);
}
static BOOL setActive(id self,SEL cmd,BOOL active,AVAudioSessionSetActiveOptions options,NSError **error) {
    // Re-read at activation, not only in the loader constructor: registration and bootstrap
    // can settle between process injection and the application's first audio activation.
    if(active) update();
    AVAudioSession *s=self;
    // Never alter recording, telephony, VoiceProcessingIO or route-selection options.
    if(active && enabled.load() && mixing.load() &&
       ([s.category isEqual:AVAudioSessionCategoryPlayback] || [s.category isEqual:AVAudioSessionCategorySoloAmbient])) {
        if(!originalCategory) { originalCategory=s.category; originalMode=s.mode; originalOptions=s.categoryOptions; }
        NSError *mixError=nil;
        [s setCategory:AVAudioSessionCategoryPlayback mode:s.mode options:(s.categoryOptions|AVAudioSessionCategoryOptionMixWithOthers)&~AVAudioSessionCategoryOptionDuckOthers error:&mixError];
    }
    BOOL result=sessionActive(self,cmd,active,options,error);
    if(result) sessionIsActive=active;
    return result;
}
static void update(void) {
    uint64_t global=0,state=0; notify_get_state(globalToken,&global); notify_get_state(configToken,&state);
    // A zero state means the service has not published this app yet. Fail open at unity.
    bool on=SDGlobalFresh(global) && (global&(1ULL<<11));
    bool wasEnabled=enabled.exchange(on); bool wasMixing=mixing.exchange(global&(1ULL<<12));
    if(on && mixing.load() && sessionIsActive && (!wasEnabled || !wasMixing)) {
        AVAudioSession *s=AVAudioSession.sharedInstance;
        if([s.category isEqual:AVAudioSessionCategoryPlayback] || [s.category isEqual:AVAudioSessionCategorySoloAmbient]) {
            if(!originalCategory) { originalCategory=s.category; originalMode=s.mode; originalOptions=s.categoryOptions; }
            [s setCategory:AVAudioSessionCategoryPlayback mode:s.mode options:(s.categoryOptions|AVAudioSessionCategoryOptionMixWithOthers)&~AVAudioSessionCategoryOptionDuckOthers error:nil];
        }
    }
    if(wasEnabled && !on && originalCategory) {
        AVAudioSession *session=AVAudioSession.sharedInstance;
        if([session.category isEqual:AVAudioSessionCategoryPlayback])
            [session setCategory:originalCategory mode:originalMode options:originalOptions error:nil];
        originalCategory=nil; originalMode=nil;
    }
    float g=state?((state&(1ULL<<10))?0.f:(state&1023)/1000.f):1.f;
    gain.store(fmaxf(0.f,fminf(1.f,g)));
    @synchronized(players) { for(AVPlayer *p in players) {
        NSNumber *base=objc_getAssociatedObject(p,baseKey);
        if(base) playerVolume(p,@selector(setVolume:),base.floatValue*(backend.load()==1?1.f:effective()));
    } }
}
static void hook(const char *name,void *replacement,void **original) { void *p=dlsym(RTLD_DEFAULT,name); if(p) MSHookFunction(p,replacement,original); }
__attribute__((constructor)) static void start(void) { @autoreleasepool {
    bundleID=NSBundle.mainBundle.bundleIdentifier;
    if(!bundleID || [bundleID isEqualToString:@"com.alsinas.sounddeck"]) return;
    static_assert(std::atomic<float>::is_always_lock_free,"gain must be lock free");
    static_assert(std::atomic<uint64_t>::is_always_lock_free,"counter must be lock free");
    players=[NSHashTable weakObjectsHashTable];
    // Synchronous check tokens provide the initial state before the host activates its session.
    // Dispatch registrations alone can race initial delivery during process launch.
    if(notify_register_check(SDGainName(bundleID).UTF8String,&configToken) || notify_register_check(SD_GLOBAL,&globalToken)) return;
    int gainWatcher,globalWatcher;
    notify_register_dispatch(SDGainName(bundleID).UTF8String,&gainWatcher,dispatch_get_main_queue(),^(int t){ update(); });
    notify_register_dispatch(SD_GLOBAL,&globalWatcher,dispatch_get_main_queue(),^(int t){ update(); });
    notify_register_check(SDClientName(getpid()).UTF8String,&clientToken);
    update();
    hook("AudioUnitSetProperty",(void *)setProperty,(void **)&originalSetProperty);
    hook("AudioUnitInitialize",(void *)initialize,(void **)&originalInitialize);
    hook("AudioComponentInstanceDispose",(void *)dispose,(void **)&originalDispose);
    MSHookMessageEx(AVPlayer.class,@selector(setVolume:),(IMP)setPlayerVolume,(IMP *)&playerVolume);
    MSHookMessageEx(AVPlayer.class,@selector(volume),(IMP)getPlayerVolume,(IMP *)&playerGetVolume);
    MSHookMessageEx(AVPlayer.class,@selector(setRate:),(IMP)setPlayerRate,(IMP *)&playerRate);
    MSHookMessageEx(AVAudioSession.class,@selector(setActive:withOptions:error:),(IMP)setActive,(IMP *)&sessionActive);
    heartbeat=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(heartbeat,DISPATCH_TIME_NOW,NSEC_PER_SEC,100*NSEC_PER_MSEC);
    __block uint64_t previous=0;
    dispatch_source_set_event_handler(heartbeat,^{
        uint64_t global=0; notify_get_state(globalToken,&global);
        bool shouldEnable=SDGlobalFresh(global) && (global&(1ULL<<11));
        if(shouldEnable!=enabled.load()) update();
        uint64_t current=frames.load(); BOOL active=current!=previous; previous=current;
        if(backend.load()==3) { @synchronized(players) { for(AVPlayer *p in players) if(p.rate!=0) active=YES; } }
        uint64_t state=SDClientState(active,backend.load(),(unsigned)lroundf(effective()*1000),inputRMS.load(),outputRMS.load());
        notify_set_state(clientToken,state);
    }); dispatch_resume(heartbeat);
} }
