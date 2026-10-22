// Modern AUAudioUnit hardware-output providers (including Web Audio's block-based path).
// Allocation and format lookup happen at setup, never inside the render block.
#include <memory>
@interface SDProviderState:NSObject {
@public std::shared_ptr<Unit> dsp;
}
@property(copy) AURenderPullInputBlock wrapped;
@end
@implementation SDProviderState
@end
static const void *providerKey=&providerKey,*engineProviderKey=&engineProviderKey;
static Class providerBridgeClass;
static IMP providerSetters[2],providerResources[2][2];
static thread_local bool insideProviderSetter=false,insideProviderResource[2]={false,false};
static id (*providerInit)(id,SEL,AudioComponentDescription,AudioComponentInstantiationOptions,NSError **);
static void refreshProvider(AUAudioUnit *object) {
    SDProviderState *box=objc_getAssociatedObject(object,providerKey); if(!box) return;
    Unit *u=box->dsp.get(); u->ready.store(0);
    if(!object.inputBusses.count) return;
    const AudioStreamBasicDescription *f=object.inputBusses[0].format.streamDescription;
    if(!f) return; SDPCMFormat format=SDDescribePCM(*f); if(!format.bytes) return;
    u->format=format; u->ramp.store(MAX(1,(unsigned)(f->mSampleRate*.005))); u->ready.store(1,std::memory_order_release);
}
static bool directMethod(Class cls,SEL selector) {
    unsigned n=0; Method *methods=class_copyMethodList(cls,&n); bool found=false;
    for(unsigned i=0;i<n;i++) if(method_getName(methods[i])==selector) found=true;
    free(methods); return found;
}
static int providerClassIndex(id object) { return providerBridgeClass && [object isKindOfClass:providerBridgeClass]?1:0; }
static void setProvider(AUAudioUnit *object,SEL selector,AURenderPullInputBlock block) {
    int index=insideProviderSetter?0:providerClassIndex(object);
    IMP original=providerSetters[index] ?: providerSetters[0];
    if(insideProviderSetter) { ((void(*)(id,SEL,id))original)(object,selector,block); return; }
    AudioComponentDescription desc=object.componentDescription;
    SDProviderState *old=objc_getAssociatedObject(object,providerKey);
    NSNumber *engine=objc_getAssociatedObject(object,engineProviderKey);
    struct BlockLayout { void *isa; int flags,reserved; void *invoke; };
    const void *invoke=block?((const BlockLayout *)(__bridge const void *)block)->invoke:nullptr;
    bool intercept=block && !nativeOwner && desc.componentType==kAudioUnitType_Output && desc.componentSubType==kAudioUnitSubType_RemoteIO && engine.intValue!=1 && (engine.intValue==2 || hostCode(invoke));
    AURenderPullInputBlock replacement=block;
    if(intercept && block!=old.wrapped) {
        SDProviderState *box=[SDProviderState new]; box->dsp=std::make_shared<Unit>(); box->dsp->path.store(engine.intValue==2?7:1);
        objc_setAssociatedObject(object,providerKey,box,OBJC_ASSOCIATION_RETAIN_NONATOMIC); refreshProvider(object);
        auto state=box->dsp; AURenderPullInputBlock originalBlock=[block copy];
        replacement=^AUAudioUnitStatus(AudioUnitRenderActionFlags *flags,const AudioTimeStamp *time,AUAudioFrameCount n,NSInteger bus,AudioBufferList *data){
            AUAudioUnitStatus status=originalBlock(flags,time,n,bus,data); if(!status) process(state.get(),n,data); return status;
        };
        box.wrapped=replacement;
    } else if(!block) objc_setAssociatedObject(object,providerKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    insideProviderSetter=true;
    @try { ((void(*)(id,SEL,id))original)(object,selector,replacement); } @finally { insideProviderSetter=false; }
}
template<int K> static BOOL providerResource(id object,SEL selector,NSError **error) {
    int index=insideProviderResource[K]?0:providerClassIndex(object);
    IMP original=providerResources[K][index] ?: providerResources[K][0];
    bool nested=insideProviderResource[K]; insideProviderResource[K]=true;
    BOOL ok;
    @try { if(!nested) refreshProvider(object); ok=((BOOL(*)(id,SEL,NSError **))original)(object,selector,error); }
    @finally { insideProviderResource[K]=nested; }
    if(!nested && ok) refreshProvider(object); return ok;
}
static void registerProviderClass(Class cls,int index) {
    if(!cls || (index==1 && cls==AUAudioUnit.class)) return;
    std::lock_guard<std::recursive_mutex> lock(SDControlMutex());
    if(index==1) { if(providerBridgeClass) return; providerBridgeClass=cls; }
    SEL setter=@selector(setOutputProvider:);
    if(index==0 || directMethod(cls,setter)) MSHookMessageEx(cls,setter,(IMP)setProvider,&providerSetters[index]);
    SEL selectors[]={@selector(allocateRenderResourcesAndReturnError:),@selector(startHardwareAndReturnError:)};
    IMP wrappers[]={(IMP)providerResource<0>,(IMP)providerResource<1>};
    for(int k=0;k<2;k++) if([cls instancesRespondToSelector:selectors[k]] && (index==0 || directMethod(cls,selectors[k]))) MSHookMessageEx(cls,selectors[k],wrappers[k],&providerResources[k][index]);
}
static id initProvider(id self,SEL selector,AudioComponentDescription desc,AudioComponentInstantiationOptions options,NSError **error) {
    id object=providerInit(self,selector,desc,options,error);
    if(object && desc.componentType==kAudioUnitType_Output && desc.componentSubType==kAudioUnitSubType_RemoteIO) registerProviderClass(object_getClass(object),1);
    return object;
}
static void markEngineProvider(AUAudioUnit *unit,BOOL legacyTap) { if(unit) objc_setAssociatedObject(unit,engineProviderKey,legacyTap?@1:@2,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void installProviders(void) {
    registerProviderClass(AUAudioUnit.class,0);
    MSHookMessageEx(AUAudioUnit.class,@selector(initWithComponentDescription:options:error:),(IMP)initProvider,(IMP *)&providerInit);
}
