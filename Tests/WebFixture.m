#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#include <math.h>
#include <stdatomic.h>
#include <notify.h>
#include <unistd.h>
static _Atomic(unsigned) buffers;
static int sessionToken=-1,meterToken=-1;
static NSData *wavData(void) {
    NSMutableData *d=[NSMutableData data]; uint16_t s;
    #define A(type,val) do { type x=(val); [d appendBytes:&x length:sizeof(x)]; } while(0)
    A(uint32_t,0x46464952); A(uint32_t,0); A(uint32_t,0x45564157); A(uint32_t,0x20746d66); A(uint32_t,16);
    A(uint16_t,1); A(uint16_t,1); A(uint32_t,44100); A(uint32_t,88200); A(uint16_t,2); A(uint16_t,16); A(uint32_t,0x61746164);
    for(NSUInteger i=0;i<44100*2;i++) { s=(uint16_t)(int16_t)lround(0.08*32767.*sin(2*M_PI*440.*i/44100.)); [d appendBytes:&s length:2]; }
    uint32_t size=(uint32_t)(d.length-8), dataSize=(uint32_t)(d.length-44); [d replaceBytesInRange:NSMakeRange(4,4) withBytes:&size]; [d replaceBytesInRange:NSMakeRange(40,4) withBytes:&dataSize];
    #undef A
    return d;
}
@interface WebDelegate:UIResponder<UIApplicationDelegate>
@property(strong,nonatomic) UIWindow *window;
@property(strong,nonatomic) WKWebView *web;
@end
@implementation WebDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSString *bid=NSBundle.mainBundle.bundleIdentifier;
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *vc=[UIViewController new]; vc.view.backgroundColor=UIColor.systemBackgroundColor;
    WKWebViewConfiguration *config=[WKWebViewConfiguration new];
    config.allowsInlineMediaPlayback=YES; config.mediaTypesRequiringUserActionForPlayback=WKAudiovisualMediaTypeNone;
    self.web=[[WKWebView alloc] initWithFrame:vc.view.bounds configuration:config]; self.web.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:self.web]; self.window.rootViewController=vc; [self.window makeKeyAndVisible];
    AVAudioSession *session=AVAudioSession.sharedInstance; [session setCategory:AVAudioSessionCategoryPlayback error:nil]; [session setPreferredSampleRate:48000 error:nil]; [session setActive:YES error:nil];
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"sounddeck-web.wav"]; [wavData() writeToFile:path atomically:YES];
#ifdef SD_WEB_MEDIA_ONLY
    NSString *script=@"a.play().catch(e=>document.title=e.message);";
#else
    NSString *script=@"window.ctx=new AudioContext();window.osc=ctx.createOscillator();osc.frequency.value=440;window.gain=ctx.createGain();gain.gain.value=0.08;osc.connect(gain);gain.connect(ctx.destination);osc.start();try{ctx.resume()}catch(e){};a.play().catch(e=>document.title=e.message);";
#endif
    NSString *html=[NSString stringWithFormat:@"<html><body style='margin:0;background:#111;color:#fff;font:24px -apple-system'><p style='padding:20px'>SoundDeck WebKit fixture · 440 Hz</p><audio id='a' src='file://%@' autoplay loop controls></audio><script>%@</script></body></html>",path,script];
    NSURL *base=[NSURL fileURLWithPath:NSTemporaryDirectory()];
    [self.web loadHTMLString:html baseURL:base];
    notify_register_check([@"com.alsinas.sounddeck.session." stringByAppendingString:bid].UTF8String,&sessionToken);
    notify_register_check([@"com.alsinas.sounddeck.test." stringByAppendingString:bid].UTF8String,&meterToken);
    [NSTimer scheduledTimerWithTimeInterval:.5 repeats:YES block:^(NSTimer *t){
        if(sessionToken>=0) notify_set_state(sessionToken,((uint64_t)(uint32_t)getpid()<<32)|(uint32_t)session.categoryOptions);
        if(meterToken>=0) notify_set_state(meterToken,((uint64_t)atomic_load(&buffers)<<32)|0);
        atomic_fetch_add(&buffers,1);
    }];
    return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(WebDelegate.class)); } }
