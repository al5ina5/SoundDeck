// Included once by Runtime.mm. Native API contexts are never used by the PCM render callback.
struct QueueContext {
    std::atomic<AudioQueueRef> queue{nullptr}; std::atomic<float> base{1}; std::atomic<bool> parent{false},disposing{false};
};
static QueueContext queues[128];
static OSStatus (*queueNew)(const AudioStreamBasicDescription *,AudioQueueOutputCallback,void *,CFRunLoopRef,CFStringRef,UInt32,AudioQueueRef *);
static OSStatus (*queueSet)(AudioQueueRef,AudioQueueParameterID,AudioQueueParameterValue);
static OSStatus (*queueGet)(AudioQueueRef,AudioQueueParameterID,AudioQueueParameterValue *);
static OSStatus (*queueDispose)(AudioQueueRef,Boolean);
static QueueContext *findQueue(AudioQueueRef q) { if(!q) return nullptr; for(auto &c:queues) if(c.queue.load(std::memory_order_acquire)==q) return &c; return nullptr; }
static OSStatus newQueue(const AudioStreamBasicDescription *f,AudioQueueOutputCallback cb,void *ref,CFRunLoopRef loop,CFStringRef mode,UInt32 flags,AudioQueueRef *out) {
    OSStatus result=queueNew(f,cb,ref,loop,mode,flags,out);
    if(!result && out && *out) {
        std::lock_guard<std::recursive_mutex> lock(SDControlMutex());
        for(auto &c:queues) if(!c.queue.load() && !c.disposing.load()) {
            float base=1; queueGet(*out,kAudioQueueParam_Volume,&base);
            c.base.store(base); c.parent.store(nativeOwner!=nullptr || !hostCode(__builtin_return_address(0))); c.queue.store(*out,std::memory_order_release);
            if(!c.parent.load()) queueSet(*out,kAudioQueueParam_Volume,base*effective()); break;
        }
    } return result;
}
static OSStatus setQueueParameter(AudioQueueRef q,AudioQueueParameterID parameter,AudioQueueParameterValue value) {
    // This API can be called from the host's queue callback: bounded atomic lookup, no locks/allocations.
    QueueContext *c=findQueue(q);
    if(c && parameter==kAudioQueueParam_Volume) {
        if(nativeOwner) c->parent.store(true);
        if(!c->parent.load()) { float base=c->base.exchange(value); OSStatus result=queueSet(q,parameter,value*effective()); if(result) c->base.store(base); return result; }
    }
    return queueSet(q,parameter,value);
}
static OSStatus getQueueParameter(AudioQueueRef q,AudioQueueParameterID parameter,AudioQueueParameterValue *out) {
    OSStatus result=queueGet(q,parameter,out); QueueContext *c=findQueue(q);
    if(!result && out && c && !c->parent.load() && parameter==kAudioQueueParam_Volume) *out=c->base.load(); return result;
}
static OSStatus disposeQueue(AudioQueueRef q,Boolean immediate) {
    QueueContext *c;
    { std::lock_guard<std::recursive_mutex> lock(SDControlMutex()); c=findQueue(q); if(c) { c->disposing.store(true); c->queue.store(nullptr); } }
    OSStatus result=queueDispose(q,immediate);
    { std::lock_guard<std::recursive_mutex> lock(SDControlMutex()); if(c) { if(result) c->queue.store(q); c->disposing.store(false); } } return result;
}
static NSHashTable *objects[3];
static const void *volumeKey=&volumeKey;
static IMP setters[3],getters[3];
static BOOL (*audioPlay)(id,SEL);
static BOOL (*audioPlayAt)(id,SEL,NSTimeInterval);
static void (*videoPlay)(id,SEL),(*videoRate)(id,SEL,float);
static void (*sampleEnqueue)(id,SEL,CMSampleBufferRef);
static unsigned objectPath(int index) { return index==0?3:(index==1?4:5); }
static float readBase(id object,int index) {
    NSNumber *number=objc_getAssociatedObject(object,volumeKey);
    return number?number.floatValue:((float(*)(id,SEL))getters[index])(object,@selector(volume));
}
static void setNative(id object,int index,float base) {
    void *old=nativeOwner; nativeOwner=(__bridge void *)object;
    ((void(*)(id,SEL,float))setters[index])(object,@selector(setVolume:),base*effective());
    nativeOwner=old;
}
static void track(id object,int index) {
    @synchronized(objects[index]) {
        if(!objc_getAssociatedObject(object,volumeKey)) objc_setAssociatedObject(object,volumeKey,@(readBase(object,index)),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [objects[index] addObject:object];
    }
    setNative(object,index,readBase(object,index));
}
template<int K> static void setObjectVolume(id object,SEL,float value) {
    objc_setAssociatedObject(object,volumeKey,@(value),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @synchronized(objects[K]) { [objects[K] addObject:object]; }
    setNative(object,K,value);
}
template<int K> static float getObjectVolume(id object,SEL) { return readBase(object,K); }
static BOOL playAudio(id object,SEL cmd) {
    track(object,1); void *old=nativeOwner; nativeOwner=(__bridge void *)object;
    BOOL ok=audioPlay(object,cmd); nativeOwner=old; setNative(object,1,readBase(object,1)); return ok;
}
static BOOL playAudioAt(id object,SEL cmd,NSTimeInterval time) {
    track(object,1); void *old=nativeOwner; nativeOwner=(__bridge void *)object;
    BOOL ok=audioPlayAt(object,cmd,time); nativeOwner=old; setNative(object,1,readBase(object,1)); return ok;
}
static void playVideo(id object,SEL cmd) {
    track(object,0); void *old=nativeOwner; nativeOwner=(__bridge void *)object;
    videoPlay(object,cmd); nativeOwner=old; setNative(object,0,readBase(object,0));
}
static void rateVideo(id object,SEL cmd,float rate) {
    track(object,0); void *old=nativeOwner; nativeOwner=(__bridge void *)object;
    videoRate(object,cmd,rate); nativeOwner=old;
}
static void enqueueSample(id object,SEL cmd,CMSampleBufferRef buffer) {
    if(!objc_getAssociatedObject(object,volumeKey)) track(object,2);
    void *old=nativeOwner; nativeOwner=(__bridge void *)object; sampleEnqueue(object,cmd,buffer); nativeOwner=old;
}
static NSArray *tracked(int index) { @synchronized(objects[index]) { return objects[index].allObjects ?: @[]; } }
static void applyNative(void) {
    for(int i=0;i<3;i++) if(objects[i] && setters[i]) for(id object in tracked(i)) setNative(object,i,readBase(object,i));
    std::lock_guard<std::recursive_mutex> lock(SDControlMutex());
    for(auto &c:queues) { AudioQueueRef q=c.queue.load(); if(q && !c.parent.load()) queueSet(q,kAudioQueueParam_Volume,c.base.load()*effective()); }
}
static NativeStatus nativeStatus(void) {
    NativeStatus status;
    for(int i=0;i<3;i++) for(id object in tracked(i)) {
        bool active=false;
        if(i==0) {
            AVPlayer *p=object; bool audio=false;
            for(AVPlayerItemTrack *t in p.currentItem.tracks) if(t.enabled && [t.assetTrack.mediaType isEqual:AVMediaTypeAudio]) audio=true;
            active=audio && p.timeControlStatus==AVPlayerTimeControlStatusPlaying;
        } else if(i==1) active=[(AVAudioPlayer *)object isPlaying];
        else { AVSampleBufferAudioRenderer *r=object; active=r.status==AVQueuedSampleBufferRenderingStatusRendering && r.timebase && CMTimebaseGetRate(r.timebase)!=0; }
        status.mask|=1U<<objectPath(i);
        if(active) { status.active=true; status.count++; status.path=objectPath(i); status.base=readBase(object,i); status.actual=((float(*)(id,SEL))getters[i])(object,@selector(volume)); }
    }
    std::lock_guard<std::recursive_mutex> lock(SDControlMutex());
    for(auto &c:queues) { AudioQueueRef q=c.queue.load(); if(!q || c.parent.load()) continue;
        status.mask|=1U<<2; UInt32 running=0,size=sizeof(running);
        if(!AudioQueueGetProperty(q,kAudioQueueProperty_IsRunning,&running,&size) && running) {
            status.active=true; status.count++; status.path=2; status.base=c.base.load(); queueGet(q,kAudioQueueParam_Volume,&status.actual);
        }
    } return status;
}
static void installNative(void) {
    hook("AudioQueueNewOutput",(void *)newQueue,(void **)&queueNew);
    hook("AudioQueueSetParameter",(void *)setQueueParameter,(void **)&queueSet);
    hook("AudioQueueGetParameter",(void *)getQueueParameter,(void **)&queueGet);
    hook("AudioQueueDispose",(void *)disposeQueue,(void **)&queueDispose);
    Class classes[]={AVPlayer.class,AVAudioPlayer.class,AVSampleBufferAudioRenderer.class};
    IMP set[]={ (IMP)setObjectVolume<0>,(IMP)setObjectVolume<1>,(IMP)setObjectVolume<2> };
    IMP get[]={ (IMP)getObjectVolume<0>,(IMP)getObjectVolume<1>,(IMP)getObjectVolume<2> };
    for(int i=0;i<3;i++) {
        objects[i]=[NSHashTable weakObjectsHashTable];
        MSHookMessageEx(classes[i],@selector(setVolume:),set[i],&setters[i]);
        MSHookMessageEx(classes[i],@selector(volume),get[i],&getters[i]);
    }
    MSHookMessageEx(classes[0],@selector(play),(IMP)playVideo,(IMP *)&videoPlay);
    MSHookMessageEx(classes[0],@selector(setRate:),(IMP)rateVideo,(IMP *)&videoRate);
    MSHookMessageEx(classes[1],@selector(play),(IMP)playAudio,(IMP *)&audioPlay);
    MSHookMessageEx(classes[1],@selector(playAtTime:),(IMP)playAudioAt,(IMP *)&audioPlayAt);
    MSHookMessageEx(classes[2],@selector(enqueueSampleBuffer:),(IMP)enqueueSample,(IMP *)&sampleEnqueue);
}
