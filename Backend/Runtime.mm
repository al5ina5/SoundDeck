#import "../Shared/SDProtocol.h"
#import "../Shared/SDIdentity.h"
#import "SDPCM.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#include <atomic>
#include <mutex>
#include <pthread.h>
extern "C" void MSHookFunction(void *,void *,void **);
extern "C" void MSHookMessageEx(Class,SEL,IMP,IMP *);
static std::atomic<float> gain{1};
static std::atomic<bool> enabled{false},mixing{true},playbackAllowed{true};
static std::atomic<uint64_t> frames{0};
static std::atomic<unsigned> inputRMS{0},outputRMS{0},backend{0};
static std::recursive_mutex &SDControlMutex(void) {
    // Function-local construction is ordered correctly even when called from image initializers.
    static std::recursive_mutex mutex;
    return mutex;
}
static thread_local void *nativeOwner=nullptr;
static int configToken,globalToken,clientToken,detailsToken;
static NSString *bundleID;
static dispatch_source_t heartbeat;
#ifdef SD_WEBKIT_AGENT
static constexpr bool webAgent=true;
#else
static constexpr bool webAgent=false;
#endif
static float effective(void) { return enabled.load() && playbackAllowed.load()?gain.load():1.f; }
static void update(bool touchNative=true);
static bool allowed(AVAudioSession *s);
static void applyNative(void);
static void installNative(void);
struct NativeStatus { bool active=false; unsigned path=0,mask=0,count=0; float actual=1,base=1; };
static NativeStatus nativeStatus(void);
static void hook(const char *name,void *replacement,void **original) { void *p=dlsym(RTLD_DEFAULT,name); if(p) MSHookFunction(p,replacement,original); }

// Only direct host callbacks / explicit engine output graphs get a PCM factor.
// Framework-owned RemoteIO callbacks remain under their native volume adapter, avoiding double gain.
struct Unit {
    AudioUnit unit=nullptr; AURenderCallback callback=nullptr; void *refcon=nullptr;
    SDPCMFormat format{};
    std::atomic<unsigned> mode{0},ready{0},path{1},ramp{240};
    float currentGain=1;
};
static Unit units[256]; static unsigned unitCount;
static OSStatus (*originalProperty)(AudioUnit,AudioUnitPropertyID,AudioUnitScope,AudioUnitElement,const void *,UInt32);
static OSStatus (*originalInitialize)(AudioUnit);
static OSStatus (*originalDispose)(AudioComponentInstance);
static OSStatus (*originalNew)(AudioComponent,AudioComponentInstance *);
static OSStatus (*originalStart)(AudioUnit);
static OSStatus (*originalGraphConnect)(AUGraph,AUNode,UInt32,AUNode,UInt32);
static OSStatus (*originalGraphStart)(AUGraph);
static bool isOutput(AudioUnit unit) {
    AudioComponentDescription d{};
    return !AudioComponentGetDescription(AudioComponentInstanceGetComponent(unit),&d) && d.componentType==kAudioUnitType_Output && d.componentSubType==kAudioUnitSubType_RemoteIO;
}
static Unit *findUnit(AudioUnit unit) { for(unsigned i=0;i<unitCount;i++) if(units[i].unit==unit) return &units[i]; return nullptr; }
static void refreshFormat(Unit *u) {
    u->ready.store(0,std::memory_order_release);
    AudioStreamBasicDescription f{}; UInt32 size=sizeof(f);
    if(AudioUnitGetProperty(u->unit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&f,&size)) return;
    auto format=SDDescribePCM(f); if(!format.bytes) return;
    u->format=format; u->ramp.store(MAX(1,(unsigned)(f.mSampleRate*.005)));
    u->ready.store(1,std::memory_order_release);
}
static void process(Unit *u,UInt32 n,AudioBufferList *data) {
    if(!data || !u->ready.load(std::memory_order_acquire)) return;
    const auto fmt=u->format;
    float target=effective(),initial=u->currentGain,delta=target-initial,ramp=(float)u->ramp.load();
    double before=0,after=0; size_t samples=0;
    for(UInt32 b=0;b<data->mNumberBuffers;b++) {
        AudioBuffer &buffer=data->mBuffers[b]; if(!buffer.mData) continue;
        size_t count=MIN(buffer.mDataByteSize/fmt.bytes,(size_t)n*MAX(1,buffer.mNumberChannels));
        unsigned channels=MAX(1,buffer.mNumberChannels);
        for(size_t i=0;i<count;i++) {
            auto *p=(unsigned char *)buffer.mData+i*fmt.bytes;
            double x=SDReadSample(p,fmt),g=delta==0?target:initial+delta*fminf(1,(float)(i/channels+1)/ramp);
            double y=x*g; SDWriteSample(p,fmt,y);
            if(std::isfinite(x) && std::isfinite(y)) { before+=x*x; after+=y*y; samples++; }
        }
    }
    u->currentGain=initial+delta*fminf(1,n/ramp);
    if(samples) {
        inputRMS.store((unsigned)fmin(65535.,sqrt(before/samples)*65535.));
        outputRMS.store((unsigned)fmin(65535.,sqrt(after/samples)*65535.));
        backend.store(u->path.load()); frames.fetch_add(n);
    }
}
static OSStatus render(void *context,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *time,UInt32 bus,UInt32 n,AudioBufferList *data) {
    Unit *u=(Unit *)context; OSStatus result=u->callback(u->refcon,flags,time,bus,n,data);
    if(!result && u->mode.load()==1) process(u,n,data); return result;
}
static OSStatus tap(void *context,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *,UInt32 bus,UInt32 n,AudioBufferList *data) {
    if(bus==0 && (*flags&kAudioUnitRenderAction_PostRender) && !(*flags&kAudioUnitRenderAction_PostRenderError)) {
        Unit *u=(Unit *)context; if(u->mode.load()==2) process(u,n,data);
    } return noErr;
}
static Unit *ensureUnit(AudioUnit unit) {
    if(!unit) return nullptr;
    Unit *u=findUnit(unit); if(u || !isOutput(unit) || unitCount==256) return u;
    u=&units[unitCount++]; u->unit=unit;
    if(AudioUnitAddRenderNotify(unit,tap,u)) u->unit=nullptr;
    return u->unit?u:nullptr;
}
static bool hostCode(const void *address) {
    Dl_info info{}; if(!dladdr(address,&info) || !info.dli_fname) return false;
    if(strstr(info.dli_fname,"/OpenAL.framework/")) return true;
    if(webAgent && (strstr(info.dli_fname,"WebCore") || strstr(info.dli_fname,"WebKit"))) return true;
    return strncmp(info.dli_fname,"/System/",8) && strncmp(info.dli_fname,"/usr/lib/",9) && strncmp(info.dli_fname,"/private/preboot/Cryptexes/",26);
}
static OSStatus newUnit(AudioComponent c,AudioComponentInstance *out) {
    OSStatus result=originalNew(c,out);
    if(!result && out && *out) { std::lock_guard<std::recursive_mutex> lock(SDControlMutex()); ensureUnit(*out); }
    return result;
}
static OSStatus setProperty(AudioUnit unit,AudioUnitPropertyID prop,AudioUnitScope scope,AudioUnitElement element,const void *data,UInt32 size) {
    std::lock_guard<std::recursive_mutex> lock(SDControlMutex());
    if(prop==kAudioUnitProperty_SetRenderCallback && element==0 && data && size==sizeof(AURenderCallbackStruct) && (scope==kAudioUnitScope_Input || scope==kAudioUnitScope_Global) && isOutput(unit)) {
        auto *cb=(const AURenderCallbackStruct *)data;
        if(cb->inputProc && cb->inputProc!=render && !nativeOwner && hostCode((void *)cb->inputProc)) {
            Unit *u=ensureUnit(unit);
            if(u) { u->callback=cb->inputProc; u->refcon=cb->inputProcRefCon; refreshFormat(u);
                AURenderCallbackStruct replacement={render,u};
                OSStatus result=originalProperty(unit,prop,scope,element,&replacement,sizeof(replacement));
                if(!result) { u->mode.store(1); u->path.store(1); } return result;
            }
        }
    }
    OSStatus result=originalProperty(unit,prop,scope,element,data,size);
    Unit *u=findUnit(unit);
    if(!result && prop==kAudioUnitProperty_MakeConnection && element==0 && !nativeOwner && hostCode(__builtin_return_address(0))) {
        u=ensureUnit(unit); if(u) { u->mode.store(2); u->path.store(1); }
    }
    if(!result && u && prop==kAudioUnitProperty_StreamFormat) refreshFormat(u);
    return result;
}
static OSStatus initialize(AudioUnit unit) { { std::lock_guard<std::recursive_mutex> lock(SDControlMutex()); Unit *u=ensureUnit(unit); if(u) refreshFormat(u); } return originalInitialize(unit); }
static OSStatus startOutput(AudioUnit unit) { { std::lock_guard<std::recursive_mutex> lock(SDControlMutex()); Unit *u=ensureUnit(unit); if(u) refreshFormat(u); } return originalStart(unit); }
static OSStatus dispose(AudioComponentInstance unit) {
    { std::lock_guard<std::recursive_mutex> lock(SDControlMutex()); Unit *u=findUnit(unit); if(u) u->ready.store(0); }
    OSStatus result=originalDispose(unit);
    { std::lock_guard<std::recursive_mutex> lock(SDControlMutex()); Unit *u=findUnit(unit); if(u) { if(!result) u->unit=nullptr; else refreshFormat(u); } } return result;
}
static void trackGraphOutput(AUGraph graph,AUNode node) {
    AudioUnit unit=nullptr; if(AUGraphNodeInfo(graph,node,NULL,&unit) || !unit) return;
    std::lock_guard<std::recursive_mutex> lock(SDControlMutex()); Unit *u=ensureUnit(unit);
    if(u) { u->mode.store(2); u->path.store(1); refreshFormat(u); }
}
static OSStatus connectGraph(AUGraph graph,AUNode source,UInt32 out,AUNode dest,UInt32 input) {
    OSStatus result=originalGraphConnect(graph,source,out,dest,input);
    if(!result && !nativeOwner && hostCode(__builtin_return_address(0))) trackGraphOutput(graph,dest);
    return result;
}
static OSStatus startGraph(AUGraph graph) {
    if(!nativeOwner && hostCode(__builtin_return_address(0))) {
        UInt32 count=0; if(!AUGraphGetNodeCount(graph,&count) && count<=512) for(UInt32 i=0;i<count;i++) { AUNode node; if(!AUGraphGetIndNode(graph,i,&node)) trackGraphOutput(graph,node); }
    } return originalGraphStart(graph);
}
#include "AUProviders.inc.mm"
static BOOL (*engineStart)(AVAudioEngine *,SEL,NSError **);
static BOOL startEngine(AVAudioEngine *self,SEL cmd,NSError **error) {
    { std::lock_guard<std::recursive_mutex> lock(SDControlMutex()); Unit *u=ensureUnit(self.outputNode.audioUnit); markEngineProvider(self.outputNode.AUAudioUnit,u!=nullptr); if(u) { u->path.store(7); u->mode.store(2); refreshFormat(u); } }
    BOOL ok=engineStart(self,cmd,error);
    { std::lock_guard<std::recursive_mutex> lock(SDControlMutex()); Unit *u=findUnit(self.outputNode.audioUnit); if(u) refreshFormat(u); } return ok;
}

#include "NativeAdapters.inc.mm"
static uint64_t previousFrames;
static void publishClient(void) {
    @autoreleasepool {
        uint64_t global=0; notify_get_state(globalToken,&global);
        uint64_t currentConfig=0; notify_get_state(configToken,&currentConfig);
        bool shouldEnable=SDGlobalFresh(global) && (global&(1ULL<<11)) && (!webAgent || (currentConfig&(1ULL<<13)));
        bool wasAllowed=playbackAllowed.exchange(allowed(AVAudioSession.sharedInstance));
        if(shouldEnable!=enabled.load() || wasAllowed!=playbackAllowed.load()) update();
        uint64_t current=frames.load(); BOOL pcm=current!=previousFrames; previousFrames=current;
        NativeStatus status=nativeStatus();
        unsigned path=pcm?backend.load():status.path;
        uint64_t state=SDClientState(pcm||status.active,path,(unsigned)lroundf(effective()*1000),pcm?inputRMS.load():0,pcm?outputRMS.load():0);
        if(!playbackAllowed.load()) state|=1ULL<<62;
        if(webAgent) state|=1ULL<<63;
        notify_set_state(clientToken,state);
        uint64_t detail=(status.mask|(pcm?(1U<<path):0))|((uint64_t)(unsigned)lroundf(fmaxf(0,fminf(6,status.actual))*10000)<<16)|((uint64_t)(unsigned)lroundf(fmaxf(0,fminf(6,status.base))*10000)<<32)|((uint64_t)MIN(65535,status.count)<<48);
        notify_set_state(detailsToken,detail);
    }
}
static void *webHeartbeat(void *) {
    for(;;) { @autoreleasepool { update(); publishClient(); } usleep(500000); }
    return NULL;
}

static BOOL (*sessionActive)(id,SEL,BOOL,AVAudioSessionSetActiveOptions,NSError **);
static NSString *savedCategory,*savedMode,*appliedCategory,*appliedMode;
static AVAudioSessionCategoryOptions savedOptions,appliedOptions;
static bool sessionIsActive=false;
static bool matchesApplied(AVAudioSession *s) { return appliedCategory && [s.category isEqual:appliedCategory] && [s.mode isEqual:appliedMode] && s.categoryOptions==appliedOptions; }
static bool allowed(AVAudioSession *s) { return ![s.category isEqual:AVAudioSessionCategoryRecord] && ![s.category isEqual:AVAudioSessionCategoryPlayAndRecord] && ![s.category isEqual:AVAudioSessionCategoryMultiRoute]; }
static void applyMix(AVAudioSession *s) {
    if(!allowed(s) || (![s.category isEqual:AVAudioSessionCategoryPlayback] && ![s.category isEqual:AVAudioSessionCategorySoloAmbient])) return;
    if(!matchesApplied(s)) { savedCategory=s.category; savedMode=s.mode; savedOptions=s.categoryOptions; }
    AVAudioSessionCategoryOptions options=(s.categoryOptions|AVAudioSessionCategoryOptionMixWithOthers)&~AVAudioSessionCategoryOptionDuckOthers;
    if([s setCategory:AVAudioSessionCategoryPlayback mode:s.mode options:options error:nil]) { appliedCategory=s.category; appliedMode=s.mode; appliedOptions=s.categoryOptions; }
}
static void restoreMix(void) {
    AVAudioSession *s=AVAudioSession.sharedInstance;
    if(savedCategory && matchesApplied(s)) [s setCategory:savedCategory mode:savedMode options:savedOptions error:nil];
    savedCategory=nil; savedMode=nil; appliedCategory=nil; appliedMode=nil;
}
static BOOL setActive(id self,SEL cmd,BOOL active,AVAudioSessionSetActiveOptions options,NSError **error) {
    if(active) { playbackAllowed.store(allowed(self)); update(false); if(enabled.load() && mixing.load()) applyMix(self); }
    BOOL ok=sessionActive(self,cmd,active,options,error); if(ok) sessionIsActive=active; return ok;
}
static void update(bool touchNative) {
    uint64_t global=0,state=0; notify_get_state(globalToken,&global); notify_get_state(configToken,&state);
    bool on=SDGlobalFresh(global) && (global&(1ULL<<11)) && (!webAgent || (state&(1ULL<<13)));
    bool wasOn=enabled.exchange(on),wasMix=mixing.exchange(global&(1ULL<<12));
    gain.store(state?((state&(1ULL<<10))?0.f:fminf(1,(state&1023)/1000.f)):1.f);
    if(on && mixing.load() && sessionIsActive && (!wasOn || !wasMix)) applyMix(AVAudioSession.sharedInstance);
    if((wasOn && !on) || (wasMix && !mixing.load())) restoreMix();
    if(touchNative) applyNative();
}
__attribute__((constructor)) static void initializeSoundDeck(void) { @autoreleasepool {
    NSString *bid=NSBundle.mainBundle.bundleIdentifier;
    // Broad UIKit loading, narrow behavior: no hooks at all in SpringBoard/system helpers or our UI.
    NSString *exe=NSBundle.mainBundle.executablePath ?: @"";
    if(webAgent) { if(![bid hasPrefix:@"com.apple.WebKit."] || ![exe containsString:@"/System/"]) return; }
    else if(SDExcludedBundle(bid) || ![NSBundle.mainBundle.bundleURL.pathExtension isEqual:@"app"] || [exe rangeOfString:@".app/"].location==NSNotFound || [exe containsString:@"/System/Library/"]) return;
    bundleID=bid;
    static_assert(std::atomic<float>::is_always_lock_free && std::atomic<uint64_t>::is_always_lock_free,"render atomics must be lock-free");
    NSString *gainName=webAgent?SDProcessGainName(getpid()):SDGainName(bundleID);
    if(notify_register_check(gainName.UTF8String,&configToken) || notify_register_check(SD_GLOBAL,&globalToken)) return;
    int gainWatcher,globalWatcher;
    dispatch_queue_t workQueue=dispatch_get_main_queue();
    if(!webAgent) {
        notify_register_dispatch(gainName.UTF8String,&gainWatcher,workQueue,^(int t){ update(); });
        notify_register_dispatch(SD_GLOBAL,&globalWatcher,workQueue,^(int t){ update(); });
    }
    notify_register_check(SDClientName(getpid()).UTF8String,&clientToken);
    notify_register_check([[SDClientName(getpid()) stringByAppendingString:@".details"] UTF8String],&detailsToken);
    hook("AudioComponentInstanceNew",(void *)newUnit,(void **)&originalNew);
    hook("AudioUnitSetProperty",(void *)setProperty,(void **)&originalProperty);
    hook("AudioUnitInitialize",(void *)initialize,(void **)&originalInitialize);
    hook("AudioOutputUnitStart",(void *)startOutput,(void **)&originalStart);
    hook("AudioComponentInstanceDispose",(void *)dispose,(void **)&originalDispose);
    hook("AUGraphConnectNodeInput",(void *)connectGraph,(void **)&originalGraphConnect);
    hook("AUGraphStart",(void *)startGraph,(void **)&originalGraphStart);
    installNative();
    installProviders();
    MSHookMessageEx(AVAudioEngine.class,@selector(startAndReturnError:),(IMP)startEngine,(IMP *)&engineStart);
    MSHookMessageEx(AVAudioSession.class,@selector(setActive:withOptions:error:),(IMP)setActive,(IMP *)&sessionActive);
    update();
    if(webAgent) {
        // WebKit's extension processes do not reliably drain libdispatch sources. A dedicated
        // thread polls the same notify state and is independent of the host run loop.
        pthread_t worker; if(!pthread_create(&worker,NULL,webHeartbeat,NULL)) pthread_detach(worker);
    } else {
        heartbeat=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,workQueue);
        dispatch_source_set_timer(heartbeat,DISPATCH_TIME_NOW,NSEC_PER_SEC,100*NSEC_PER_MSEC);
        dispatch_source_set_event_handler(heartbeat,^{ publishClient(); }); dispatch_resume(heartbeat);
    }
} }
