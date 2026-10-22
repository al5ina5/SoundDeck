#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import "../Shared/SDProtocol.h"
#import "../Shared/SDMixerRow.h"
#import "../App/SDMasterVolume.h"

// Public runtime protocol names; no private framework binary or copied headers are bundled.
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
@property(strong) UIStackView *panel;
@property(strong) UILabel *summary,*route;
@property(strong) UISlider *master;
@property(strong) UITableView *table;
@property(strong) NSTimer *timer,*saveTimer;
@property(strong) NSArray *apps;
@property(strong) NSDictionary *prefs;
@property(strong) NSMutableDictionary *edits;
@property(assign) BOOL expanded;
@end
@implementation SDCCViewController
- (instancetype)init { if((self=[super init])) { _apps=@[]; _edits=[NSMutableDictionary new]; } return self; }
- (CGFloat)preferredExpandedContentHeight { return MIN(560,MAX(300,180+_apps.count*135)); }
- (CGFloat)preferredExpandedContentWidth { return MAX(280,MIN(400,UIScreen.mainScreen.bounds.size.width-64)); }
- (BOOL)providesOwnPlatter { return NO; }
- (BOOL)shouldBeginTransitionToExpandedContentModule { return YES; }
- (BOOL)shouldFinishTransitionToExpandedContentModule { return YES; }
- (BOOL)canDismissPresentedContent { return YES; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=UIColor.clearColor;
    _compact=[UIView new]; _compact.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:_compact];
    UIImageView *icon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3"]]; icon.tintColor=UIColor.labelColor; icon.contentMode=UIViewContentModeScaleAspectFit;
    UILabel *label=[UILabel new]; label.text=@"SoundDeck"; label.textColor=UIColor.labelColor; label.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]; label.textAlignment=NSTextAlignmentCenter;
    UIStackView *tile=[[UIStackView alloc] initWithArrangedSubviews:@[icon,label]]; tile.axis=UILayoutConstraintAxisVertical; tile.spacing=5; tile.translatesAutoresizingMaskIntoConstraints=NO; [_compact addSubview:tile];
    [_compact addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(expand)]];
    _compact.isAccessibilityElement=YES; _compact.accessibilityLabel=@"SoundDeck audio mixer"; _compact.accessibilityHint=@"Expand to adjust each playing app"; _compact.accessibilityTraits=UIAccessibilityTraitButton;
    UILabel *title=[UILabel new]; title.text=@"SoundDeck"; title.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2]; title.adjustsFontForContentSizeCategory=YES;
    UIButton *done=[UIButton buttonWithType:UIButtonTypeSystem]; [done setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal]; done.tintColor=UIColor.secondaryLabelColor; done.accessibilityLabel=@"Collapse SoundDeck mixer"; [done addTarget:self action:@selector(collapse) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *top=[[UIStackView alloc] initWithArrangedSubviews:@[title,done]]; top.alignment=UIStackViewAlignmentCenter;
    _route=[UILabel new]; _route.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; _route.textColor=UIColor.secondaryLabelColor; _route.numberOfLines=2;
    _master=[UISlider new]; _master.tintColor=UIColor.systemIndigoColor; _master.accessibilityLabel=@"System media master volume"; [_master addTarget:self action:@selector(masterChanged:) forControlEvents:UIControlEventValueChanged];
    _summary=[UILabel new]; _summary.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; _summary.textColor=UIColor.secondaryLabelColor; _summary.numberOfLines=2;
    _table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; _table.dataSource=self; _table.delegate=self; _table.backgroundColor=UIColor.clearColor; _table.separatorColor=UIColor.separatorColor; _table.rowHeight=UITableViewAutomaticDimension; _table.estimatedRowHeight=128; [_table registerClass:SDRow.class forCellReuseIdentifier:@"app"];
    _panel=[[UIStackView alloc] initWithArrangedSubviews:@[top,_route,_master,_summary,_table]]; _panel.axis=UILayoutConstraintAxisVertical; _panel.spacing=8; _panel.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:_panel];
    [NSLayoutConstraint activateConstraints:@[[tile.centerXAnchor constraintEqualToAnchor:_compact.centerXAnchor],[tile.centerYAnchor constraintEqualToAnchor:_compact.centerYAnchor],[icon.heightAnchor constraintEqualToConstant:25],[tile.widthAnchor constraintLessThanOrEqualToAnchor:_compact.widthAnchor constant:-8],[_compact.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[_compact.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[_compact.topAnchor constraintEqualToAnchor:self.view.topAnchor],[_compact.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],[_panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],[_panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],[_panel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:14],[_panel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-12],[done.widthAnchor constraintEqualToConstant:44],[done.heightAnchor constraintEqualToConstant:44],[_master.heightAnchor constraintEqualToConstant:32]]];
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
        NSMutableArray<SDRow *> *rows=[NSMutableArray new]; for(UITableViewCell *cell in weak.table.visibleCells) if([cell isKindOfClass:SDRow.class]) [rows addObject:(SDRow *)cell];
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
- (void)showControlCenter {
    Class cls=NSClassFromString(@"SBControlCenterController"); SEL shared=NSSelectorFromString(@"sharedInstance");
    if(![cls respondsToSelector:shared]) return;
    id c=((id(*)(id,SEL))objc_msgSend)(cls,shared); SEL present=NSSelectorFromString(@"presentAnimated:");
    if([c respondsToSelector:present]) ((void(*)(id,SEL,BOOL))objc_msgSend)(c,present,YES);
    else { present=NSSelectorFromString(@"presentAnimated:completion:"); if([c respondsToSelector:present]) ((void(*)(id,SEL,BOOL,id))objc_msgSend)(c,present,YES,nil); }
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
    NSArray *next=SDActiveApplications(status);
    BOOL tracking=NO; for(UITableViewCell *c in _table.visibleCells) if([c isKindOfClass:SDRow.class] && ((SDRow *)c).slider.tracking) tracking=YES;
    if(!tracking) { _apps=next; [_table reloadData]; }
    BOOL fresh=NSDate.date.timeIntervalSince1970-[status[@"timestamp"] doubleValue]<4;
    if(_expanded && next.count!=_apps.count && [_context respondsToSelector:NSSelectorFromString(@"expandedModuleDidUpdatePreferredSize")])
        ((void(*)(id,SEL))objc_msgSend)(_context,NSSelectorFromString(@"expandedModuleDidUpdatePreferredSize"));
    _summary.text=!fresh?@"Backend unavailable · Automatic safety bypass":([_prefs[@"disabled"] boolValue]?@"SoundDeck is bypassed":(_apps.count?[NSString stringWithFormat:@"%lu playing apps · Individual volume",(unsigned long)_apps.count]:@"Playing apps appear automatically"));
    _route.text=[NSString stringWithFormat:@"%@ · Master volume",AVAudioSession.sharedInstance.currentRoute.outputs.firstObject.portName ?: @"System audio output"];
    if(!_master.tracking) { float v=[SDMasterVolume level]; _master.enabled=v>=0; if(v>=0) _master.value=v; }
}
- (void)masterChanged:(UISlider *)slider { [SDMasterVolume setLevel:slider.value]; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return MAX(1,_apps.count); }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    if(!_apps.count) { UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; cell.backgroundColor=UIColor.clearColor; cell.textLabel.text=@"No active audio"; cell.detailTextLabel.text=@"Start playback in any app."; cell.selectionStyle=UITableViewCellSelectionStyleNone; return cell; }
    SDRow *row=[table dequeueReusableCellWithIdentifier:@"app" forIndexPath:index]; NSDictionary *app=_apps[index.row]; NSString *bid=app[@"bundleID"];
    NSMutableDictionary *entry=[_prefs[@"apps"][bid] mutableCopy] ?: [NSMutableDictionary new]; if(_edits[bid]) [entry addEntriesFromDictionary:_edits[bid]];
    row.bundleID=bid; row.nameLabel.text=app[@"name"]; row.statusLabel.text=[app[@"controllable"] boolValue]?app[@"path"]:@"Unattributed or excluded audio · Bypassed";
    row.backgroundColor=UIColor.clearColor; row.appIcon.image=[UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:UIScreen.mainScreen.scale] ?: [UIImage systemImageNamed:@"waveform"];
    row.slider.value=entry[@"gain"]?[entry[@"gain"] floatValue]:1; row.slider.enabled=row.mute.enabled=[app[@"controllable"] boolValue]; row.valueLabel.text=[NSString stringWithFormat:@"%.0f%%",row.slider.value*100];
    row.slider.accessibilityLabel=[NSString stringWithFormat:@"%@ volume",app[@"name"]]; row.mute.selected=[entry[@"muted"] boolValue]; row.mute.accessibilityLabel=[NSString stringWithFormat:@"%@ %@",row.mute.selected?@"Unmute":@"Mute",app[@"name"]];
    [row.mute setImage:[UIImage systemImageNamed:row.mute.selected?@"speaker.slash.fill":@"speaker.wave.2.fill"] forState:UIControlStateNormal];
    __weak typeof(self) weak=self; __weak SDRow *weakRow=row;
    row.change=^(NSString *identifier,float value,BOOL muteChange,BOOL muted){
        SDCCViewController *self=weak; if(!self) return;
        NSMutableDictionary *delta=[self.edits[identifier] mutableCopy] ?: [NSMutableDictionary new]; delta[@"name"]=app[@"name"]; delta[muteChange?@"muted":@"gain"]=muteChange?@(muted):@(value); self.edits[identifier]=delta;
        NSMutableDictionary *live=[self.prefs[@"apps"][identifier] mutableCopy] ?: [NSMutableDictionary new]; [live addEntriesFromDictionary:delta];
        int token; if(!notify_register_check(SDGainName(identifier).UTF8String,&token)) { notify_set_state(token,SDConfig(self.prefs,live)); notify_post(SDGainName(identifier).UTF8String); notify_cancel(token); }
        [self.saveTimer invalidate]; self.saveTimer=[NSTimer scheduledTimerWithTimeInterval:.2 repeats:NO block:^(NSTimer *timer){ [weak flush]; }];
        if(muteChange) { weakRow.mute.selected=muted; [weakRow.mute setImage:[UIImage systemImageNamed:muted?@"speaker.slash.fill":@"speaker.wave.2.fill"] forState:UIControlStateNormal]; }
    }; return row;
}
- (void)flush {
    [_saveTimer invalidate]; _saveTimer=nil;
    if(!_edits.count) return;
    if(SDUpdatePrefs(@{@"apps":[_edits copy]},nil)) { [_edits removeAllObjects]; _prefs=SDReadPrefs(); }
    [self diagnostics];
}
- (void)diagnostics {
    NSMutableArray *rows=[NSMutableArray new]; for(SDRow *row in _table.visibleCells) if([row isKindOfClass:SDRow.class]) [rows addObject:@{@"bundleID":row.bundleID ?: @"",@"gain":@(row.slider.value),@"enabled":@(row.slider.enabled)}];
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
