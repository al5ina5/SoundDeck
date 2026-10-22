#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import "../Shared/SDProtocol.h"
#import "../Shared/SDMixerRow.h"
#import "../App/SDMasterVolume.h"

@protocol CCUIContentModuleContentViewController <NSObject>
@property(nonatomic,readonly) CGFloat preferredExpandedContentHeight;
@property(nonatomic,readonly) CGFloat preferredExpandedContentWidth;
@end
@protocol CCUIContentModule <NSObject>
@property(nonatomic,readonly) UIViewController<CCUIContentModuleContentViewController> *contentViewController;
@end
@interface UIImage (SDCCIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(CGFloat)scale;
@end
@interface SDCCViewController:UIViewController<CCUIContentModuleContentViewController,UITableViewDataSource,UITableViewDelegate>
@property(strong) id context;
@property(strong) UIView *compact;
@property(strong) UIStackView *panel,*masterLine;
@property(strong) UIImageView *masterIcon;
@property(strong) UISlider *master;
@property(strong) MPVolumeView *masterFallback;
@property(strong) UITableView *table;
@property(strong) NSTimer *timer,*saveTimer;
@property(strong) NSArray *apps;
@property(strong) NSDictionary *prefs;
@property(strong) NSMutableDictionary *edits;
@property(assign) BOOL expanded;
@end
@implementation SDCCViewController
- (instancetype)init { if((self=[super init])) { _apps=@[]; _edits=[NSMutableDictionary new]; } return self; }
- (CGFloat)preferredExpandedContentHeight { return MIN(560,MAX(72,68+_apps.count*64)); }
- (CGFloat)preferredExpandedContentWidth { return MAX(280,MIN(360,UIScreen.mainScreen.bounds.size.width-64)); }
- (BOOL)providesOwnPlatter { return NO; }
- (BOOL)shouldBeginTransitionToExpandedContentMode { return YES; }
- (BOOL)shouldFinishTransitionToExpandedContentMode { return YES; }
- (BOOL)canDismissPresentedContent { return YES; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=UIColor.clearColor;
    _compact=[UIView new]; _compact.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:_compact];
    UIImageView *tileIcon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3"]];
    tileIcon.tintColor=UIColor.whiteColor; tileIcon.contentMode=UIViewContentModeScaleAspectFit;
    tileIcon.translatesAutoresizingMaskIntoConstraints=NO; [_compact addSubview:tileIcon];
    [_compact addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(expand)]];
    _compact.isAccessibilityElement=YES; _compact.accessibilityLabel=@"SoundDeck mixer"; _compact.accessibilityHint=@"Expand to adjust playing apps"; _compact.accessibilityTraits=UIAccessibilityTraitButton;

    _masterIcon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"speaker.wave.2.fill"]];
    _masterIcon.contentMode=UIViewContentModeScaleAspectFit; _masterIcon.tintColor=UIColor.whiteColor;
    _masterIcon.accessibilityLabel=@"System media volume"; _masterIcon.isAccessibilityElement=YES;
    _master=[UISlider new]; _master.minimumValue=0; _master.maximumValue=1; _master.tintColor=UIColor.systemIndigoColor;
    _master.accessibilityLabel=@"System media volume"; [_master addTarget:self action:@selector(masterChanged:) forControlEvents:UIControlEventValueChanged];
    _masterFallback=[[MPVolumeView alloc] initWithFrame:CGRectZero]; _masterFallback.showsRouteButton=NO; _masterFallback.tintColor=UIColor.systemIndigoColor;
    BOOL direct=[SDMasterVolume available]; _master.hidden=!direct; _masterFallback.hidden=direct; _masterFallback.showsVolumeSlider=!direct;
    _masterLine=[[UIStackView alloc] initWithArrangedSubviews:@[_masterIcon,_master,_masterFallback]];
    _masterLine.axis=UILayoutConstraintAxisHorizontal; _masterLine.alignment=UIStackViewAlignmentCenter; _masterLine.spacing=12;

    _table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; _table.dataSource=self; _table.delegate=self;
    _table.backgroundColor=UIColor.clearColor; _table.separatorColor=UIColor.separatorColor; _table.rowHeight=60; _table.estimatedRowHeight=60;
    [_table registerClass:SDRow.class forCellReuseIdentifier:@"app"];
    _panel=[[UIStackView alloc] initWithArrangedSubviews:@[_masterLine,_table]]; _panel.axis=UILayoutConstraintAxisVertical;
    _panel.spacing=2; _panel.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:_panel];
    [NSLayoutConstraint activateConstraints:@[
        [tileIcon.centerXAnchor constraintEqualToAnchor:_compact.centerXAnchor],[tileIcon.centerYAnchor constraintEqualToAnchor:_compact.centerYAnchor],
        [tileIcon.widthAnchor constraintEqualToConstant:27],[tileIcon.heightAnchor constraintEqualToConstant:27],
        [_compact.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[_compact.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_compact.topAnchor constraintEqualToAnchor:self.view.topAnchor],[_compact.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],[_panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [_panel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:6],[_panel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-6],
        [_masterIcon.widthAnchor constraintEqualToConstant:32],[_masterIcon.heightAnchor constraintEqualToConstant:32],[_masterLine.heightAnchor constraintEqualToConstant:52],
        [_masterFallback.heightAnchor constraintEqualToConstant:32]]];
    _panel.hidden=!_expanded; _compact.hidden=_expanded; [self refresh];
    __weak typeof(self) weak=self;
    for(NSString *verb in @[@"expand",@"capture",@"dismiss"]) {
        int token; NSString *name=[@"com.alsinas.sounddeck.cc." stringByAppendingString:verb];
        notify_register_dispatch(name.UTF8String,&token,dispatch_get_main_queue(),^(int t){
            if([verb isEqual:@"expand"]) [weak expand];
            else if([verb isEqual:@"dismiss"]) { SEL s=NSSelectorFromString(@"dismissControlCenter"); if([weak.context respondsToSelector:s]) ((void(*)(id,SEL))objc_msgSend)(weak.context,s); }
            else [weak capture];
        });
    }
#ifdef SD_TESTING
    int testToken; notify_register_dispatch("com.alsinas.sounddeck.cc.test-sliders",&testToken,dispatch_get_main_queue(),^(int token){
        NSMutableArray<SDRow *> *rows=[NSMutableArray new]; for(UITableViewCell *cell in weak.table.visibleCells) if([cell isKindOfClass:SDRow.class] && [@[@"com.alsinas.sounddeck.media.ap",@"com.alsinas.sounddeck.media.aq"] containsObject:((SDRow *)cell).bundleID]) [rows addObject:(SDRow *)cell];
        [rows sortUsingComparator:^NSComparisonResult(SDRow *a,SDRow *b){ return [a.bundleID compare:b.bundleID]; }];
        for(NSUInteger i=0;i<MIN((NSUInteger)2,rows.count);i++) { rows[i].slider.value=i?0.8f:0.2f; [rows[i].slider sendActionsForControlEvents:UIControlEventValueChanged]; }
    });
    int masterToken; notify_register_dispatch("com.alsinas.sounddeck.cc.test-master",&masterToken,dispatch_get_main_queue(),^(int token){
        float before=[SDMasterVolume level]; if(before<0) return; float target=before>0.12f?before-.05f:before+.05f;
        BOOL set=[SDMasterVolume setLevel:target]; usleep(220000); float after=[SDMasterVolume level]; [SDMasterVolume setLevel:before]; usleep(120000); float restored=[SDMasterVolume level];
        [@{@"before":@(before),@"target":@(target),@"after":@(after),@"restored":@(restored),@"set":@(set)} writeToFile:SD_DIR @"/cc-master-test.plist" atomically:YES];
    });
#endif
    [self diagnostics];
}
- (BOOL)accessibilityActivate { [self expand]; return YES; }
- (void)expand { SEL s=NSSelectorFromString(@"requestExpandModule"); if([_context respondsToSelector:s]) ((void(*)(id,SEL))objc_msgSend)(_context,s); }
- (void)collapse { SEL s=NSSelectorFromString(@"dismissModule"); if([_context respondsToSelector:s]) ((void(*)(id,SEL))objc_msgSend)(_context,s); }
- (void)willTransitionToExpandedContentMode:(BOOL)expanded { _expanded=expanded; _compact.hidden=expanded; _panel.hidden=!expanded; [self refresh]; }
- (void)didTransitionToExpandedContentMode:(BOOL)expanded { _expanded=expanded; [self diagnostics]; }
- (void)startTimer { [self refresh]; if(_timer) return; __weak typeof(self) weak=self; _timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){ [weak refresh]; }]; }
- (void)controlCenterWillPresent { [self startTimer]; }
- (void)controlCenterDidDismiss { [_timer invalidate]; _timer=nil; [self flush]; }
- (void)willBecomeActive { [self startTimer]; }
- (void)willResignActive { [self controlCenterDidDismiss]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self startTimer]; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self diagnostics]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self controlCenterDidDismiss]; }
- (void)dealloc { [_timer invalidate]; [_saveTimer invalidate]; }
- (void)refresh {
    if(!_edits.count) _prefs=SDReadPrefs();
    NSDictionary *status=[NSDictionary dictionaryWithContentsOfFile:SD_STATUS] ?: @{};
    NSArray *next=SDActiveApplications(status); NSArray *old=[_apps valueForKey:@"bundleID"],*fresh=[next valueForKey:@"bundleID"];
    if(![old isEqual:fresh]) {
        _apps=next; [_table reloadData];
        if(_expanded && [_context respondsToSelector:NSSelectorFromString(@"expandedModuleDidUpdatePreferredSize")])
            ((void(*)(id,SEL))objc_msgSend)(_context,NSSelectorFromString(@"expandedModuleDidUpdatePreferredSize"));
    }
    if(!_master.tracking) { float v=[SDMasterVolume level]; _master.enabled=v>=0; if(v>=0) _master.value=v; }
}
- (void)masterChanged:(UISlider *)slider { [SDMasterVolume setLevel:slider.value]; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return _apps.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    SDRow *row=[table dequeueReusableCellWithIdentifier:@"app" forIndexPath:index]; NSDictionary *app=_apps[index.row];
    NSString *bid=app[@"bundleID"],*name=app[@"name"] ?: bid;
    NSMutableDictionary *entry=[_prefs[@"apps"][bid] mutableCopy] ?: [NSMutableDictionary new];
    if(_edits[bid]) [entry addEntriesFromDictionary:_edits[bid]];
    row.bundleID=bid; row.appIcon.image=[UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:UIScreen.mainScreen.scale] ?: [UIImage systemImageNamed:@"waveform"];
    row.slider.value=[entry[@"muted"] boolValue]?0:(entry[@"gain"]?[entry[@"gain"] floatValue]:1);
    row.slider.enabled=[app[@"controllable"] boolValue]; row.slider.accessibilityLabel=[NSString stringWithFormat:@"%@ volume",name];
    row.slider.accessibilityValue=row.slider.value<=0?@"Muted":[NSString stringWithFormat:@"%.0f percent",row.slider.value*100];
    __weak typeof(self) weak=self;
    row.change=^(NSString *identifier,float value,BOOL muteChange,BOOL muted){
        SDCCViewController *controller=weak; if(!controller) return;
        NSMutableDictionary *delta=[controller.edits[identifier] mutableCopy] ?: [NSMutableDictionary new];
        delta[@"name"]=name; delta[@"gain"]=@(value); delta[@"muted"]=@NO; controller.edits[identifier]=delta;
        NSMutableDictionary *live=[controller.prefs[@"apps"][identifier] mutableCopy] ?: [NSMutableDictionary new]; [live addEntriesFromDictionary:delta];
        int token; if(!notify_register_check(SDGainName(identifier).UTF8String,&token)) { notify_set_state(token,SDConfig(controller.prefs,live)); notify_post(SDGainName(identifier).UTF8String); notify_cancel(token); }
        [controller.saveTimer invalidate]; controller.saveTimer=[NSTimer scheduledTimerWithTimeInterval:.2 repeats:NO block:^(NSTimer *timer){ [weak flush]; }];
    };
    return row;
}
- (void)flush {
    [_saveTimer invalidate]; _saveTimer=nil; if(!_edits.count) return;
    if(SDUpdatePrefs(@{@"apps":[_edits copy]},nil)) { [_edits removeAllObjects]; _prefs=SDReadPrefs(); }
    [self diagnostics];
}
- (void)diagnostics {
    NSMutableArray *rows=[NSMutableArray new];
    for(SDRow *row in _table.visibleCells) if([row isKindOfClass:SDRow.class]) [rows addObject:@{@"bundleID":row.bundleID ?: @"",@"gain":@(row.slider.value),@"enabled":@(row.slider.enabled)}];
    [@{@"version":SD_VERSION,@"host":NSBundle.mainBundle.bundleIdentifier ?: @"",@"expanded":@(_expanded),@"visible":@(self.view.window!=nil),@"rows":rows,@"contextClass":NSStringFromClass([_context class]) ?: @"",@"parentClass":NSStringFromClass(self.parentViewController.class) ?: @""} writeToFile:SD_DIR @"/cc-diagnostics.plist" atomically:YES];
}
- (void)capture {
    [self diagnostics]; UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:self.view.bounds];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){ [self.view.layer renderInContext:context.CGContext]; }];
    [UIImagePNGRepresentation(image) writeToFile:SD_DIR @"/cc-capture.png" atomically:YES];
}
@end
@interface SDCCModule:NSObject<CCUIContentModule>
@property(strong) SDCCViewController *controller;
@end
@implementation SDCCModule
- (instancetype)init { if((self=[super init])) _controller=[SDCCViewController new]; return self; }
- (UIViewController<CCUIContentModuleContentViewController> *)contentViewController { return _controller; }
- (UIViewController *)backgroundViewController { return nil; }
- (void)setContentModuleContext:(id)context { _controller.context=context; }
@end
