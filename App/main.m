#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import "../Shared/SDProtocol.h"
#import "SDMasterVolume.h"
#import "../Shared/SDMixerRow.h"
@interface UIImage (SDPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(CGFloat)scale;
@end
@interface SDController : UIViewController<UITableViewDataSource,UITableViewDelegate>
@property(strong) NSDictionary *status;
@property(strong) NSMutableDictionary *prefs;
@property(strong) NSDictionary *savedPreferences;
@property(strong) NSArray *active;
@property(strong) NSTimer *timer,*saveTimer;
@property(strong) UIView *card;
@property(strong) UITableView *tableView;
@property(strong) NSLayoutConstraint *cardHeight,*cardWidth;
@property(strong) UISlider *masterSlider;
@property(strong) MPVolumeView *masterFallback;
@property(strong) UIImageView *masterIcon;
@end
@implementation SDController
- (void)capture {
    UIWindow *window=self.view.window; if(!window) return;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){ [window.layer renderInContext:context.CGContext]; }];
    [UIImagePNGRepresentation(image) writeToFile:SD_DIR @"/capture.png" atomically:YES];
    NSMutableArray *rows=[NSMutableArray new];
    for(UITableViewCell *cell in _tableView.visibleCells) if([cell isKindOfClass:SDRow.class]) {
        SDRow *row=(SDRow *)cell;
        [rows addObject:@{@"bundleID":row.bundleID ?: @"",@"gain":@(row.slider.value),@"iconPresent":@(row.appIcon.image!=nil),
          @"sliderAccessible":@(row.slider.accessibilityLabel.length>0),@"touchTargetHeight":@(row.bounds.size.height),@"ambiguous":@(row.contentView.hasAmbiguousLayout)}];
    }
    [@{@"phase":@"captured",@"state":@(UIApplication.sharedApplication.applicationState),@"width":@(window.bounds.size.width),@"height":@(window.bounds.size.height),@"style":@(window.traitCollection.userInterfaceStyle),@"rows":rows} writeToFile:SD_DIR @"/ui-diagnostics.plist" atomically:YES];
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    _card=[UIView new]; _card.translatesAutoresizingMaskIntoConstraints=NO; _card.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    _card.layer.cornerRadius=22; _card.clipsToBounds=YES; [self.view addSubview:_card];
    _tableView=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; _tableView.translatesAutoresizingMaskIntoConstraints=NO;
    _tableView.dataSource=self; _tableView.delegate=self; _tableView.backgroundColor=UIColor.clearColor;
    _tableView.separatorColor=UIColor.separatorColor; _tableView.separatorInset=UIEdgeInsetsMake(0,68,0,18);
    _tableView.rowHeight=64; _tableView.estimatedRowHeight=64; _tableView.showsVerticalScrollIndicator=NO;
    [_tableView registerClass:SDRow.class forCellReuseIdentifier:@"app"]; [_card addSubview:_tableView];
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,600,64)];
    _masterIcon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"speaker.wave.2.fill"]];
    _masterIcon.contentMode=UIViewContentModeScaleAspectFit; _masterIcon.tintColor=UIColor.labelColor;
    _masterIcon.isAccessibilityElement=YES; _masterIcon.accessibilityLabel=@"System media volume";
    _masterSlider=[UISlider new]; _masterSlider.minimumValue=0; _masterSlider.maximumValue=1;
    _masterSlider.tintColor=UIColor.systemIndigoColor; _masterSlider.accessibilityLabel=@"System media volume";
    [_masterSlider addTarget:self action:@selector(masterChanged:) forControlEvents:UIControlEventValueChanged];
    _masterFallback=[[MPVolumeView alloc] initWithFrame:CGRectZero]; _masterFallback.showsRouteButton=NO; _masterFallback.accessibilityLabel=@"System media volume";
    _masterFallback.tintColor=UIColor.systemIndigoColor;
    BOOL direct=[SDMasterVolume available]; _masterSlider.hidden=!direct; _masterFallback.hidden=direct; _masterFallback.showsVolumeSlider=!direct;
    UIStackView *line=[[UIStackView alloc] initWithArrangedSubviews:@[_masterIcon,_masterSlider,_masterFallback]];
    line.axis=UILayoutConstraintAxisHorizontal; line.alignment=UIStackViewAlignmentCenter; line.spacing=14; line.translatesAutoresizingMaskIntoConstraints=NO;
    [header addSubview:line];
    [NSLayoutConstraint activateConstraints:@[[line.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:18],
        [line.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-18],
        [line.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [line.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8],
        [_masterIcon.widthAnchor constraintEqualToConstant:36],[_masterIcon.heightAnchor constraintEqualToConstant:36],
        [_masterFallback.heightAnchor constraintEqualToConstant:32]]];
    _tableView.tableHeaderView=header;
    _cardHeight=[_card.heightAnchor constraintEqualToConstant:64];
    _cardWidth=[_card.widthAnchor constraintEqualToConstant:MIN(620,UIScreen.mainScreen.bounds.size.width-48)];
    [NSLayoutConstraint activateConstraints:@[[_card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],_cardWidth,_cardHeight,
        [_tableView.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor],[_tableView.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor],
        [_tableView.topAnchor constraintEqualToAnchor:_card.topAnchor],[_tableView.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor]]];
    [self refresh];
    int captureToken; __weak typeof(self) captureSelf=self;
    notify_register_dispatch("com.alsinas.sounddeck.capture",&captureToken,dispatch_get_main_queue(),^(int token){ [captureSelf capture]; });
#ifdef SD_TESTING
    for(NSString *command in @[@"sliders",@"mute",@"unmute",@"master",@"portrait",@"landscape"]) {
        int testToken; NSString *name=[@"com.alsinas.sounddeck.test-ui." stringByAppendingString:command];
        notify_register_dispatch(name.UTF8String,&testToken,dispatch_get_main_queue(),^(int token){
            SDController *controller=captureSelf;
            if([command isEqual:@"master"]) {
                float initial=[SDMasterVolume level]; if(initial<0) return;
                float requested=initial>0.1f?initial*.5f:fminf(1.f,initial+0.15f);
                controller.masterSlider.value=requested; [controller.masterSlider sendActionsForControlEvents:UIControlEventValueChanged];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                    float changed=AVAudioSession.sharedInstance.outputVolume;
                    controller.masterSlider.value=initial; [controller.masterSlider sendActionsForControlEvents:UIControlEventValueChanged];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                        [@{@"initial":@(initial),@"requested":@(requested),@"changed":@(changed),@"restored":@(AVAudioSession.sharedInstance.outputVolume),@"restoredNative":@([SDMasterVolume level]),@"method":@"UIKit slider action to AVSystemController; measured with AVAudioSession.outputVolume"} writeToFile:SD_DIR @"/master-test.plist" atomically:YES];
                    });
                }); return;
            }
            if([command isEqual:@"portrait"] || [command isEqual:@"landscape"]) {
                if(@available(iOS 16.0,*)) {
                    UIWindowSceneGeometryPreferencesIOS *geometry=[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:[command isEqual:@"portrait"]?UIInterfaceOrientationMaskPortrait:UIInterfaceOrientationMaskLandscapeLeft];
                    [controller.view.window.windowScene requestGeometryUpdateWithPreferences:geometry errorHandler:^(NSError *error){ [@{@"error":error.localizedDescription} writeToFile:SD_DIR @"/rotation-test.plist" atomically:YES]; }];
                } return;
            }
            for(UITableViewCell *cell in controller.tableView.visibleCells) if([cell isKindOfClass:SDRow.class]) {
                SDRow *row=(SDRow *)cell; if(![row.bundleID hasSuffix:@"sounddeck.toneA"] && ![row.bundleID hasSuffix:@"sounddeck.toneB"]) continue;
                if([command isEqual:@"sliders"]) row.slider.value=[row.bundleID hasSuffix:@"toneA"]?.2:.8;
                else if([row.bundleID hasSuffix:@"toneA"]) row.slider.value=[command isEqual:@"mute"]?0:.2;
                row.slider.accessibilityValue=row.slider.value<=0?@"Muted":[NSString stringWithFormat:@"%.0f percent",row.slider.value*100];
                [row.slider sendActionsForControlEvents:UIControlEventValueChanged];
            }
        });
    }
#endif
    __weak typeof(self) weak=self;
    _timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){ [weak refresh]; }];
}
- (void)dealloc { [_timer invalidate]; [_saveTimer invalidate]; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _cardWidth.constant=MIN(620,MAX(280,self.view.bounds.size.width-48));
    UIView *header=_tableView.tableHeaderView; if(!header) return;
    CGFloat height=64,width=_tableView.bounds.size.width;
    if(fabs(header.bounds.size.height-height)>.5 || fabs(header.bounds.size.width-width)>.5) {
        CGRect frame=header.frame; frame.size=CGSizeMake(width,height); header.frame=frame; _tableView.tableHeaderView=header;
    }
    _cardHeight.constant=MIN(MAX(64,self.view.bounds.size.height-48),64+_active.count*64);
}
- (void)refresh {
    if(!_saveTimer) { _prefs=[SDReadPrefs() mutableCopy]; _savedPreferences=[_prefs copy]; }
    self.view.window.overrideUserInterfaceStyle=[_prefs[@"appearance"] integerValue];
    float master=[SDMasterVolume level]; if(master>=0 && !_masterSlider.tracking) { _masterSlider.value=master; _masterSlider.accessibilityValue=[NSString stringWithFormat:@"%.0f percent",master*100]; }
    _status=[NSDictionary dictionaryWithContentsOfFile:SD_STATUS] ?: @{};
    NSArray *active=SDActiveApplications(_status); NSArray *old=[_active valueForKey:@"bundleID"],*next=[active valueForKey:@"bundleID"];
    BOOL changed=![old isEqual:next]; _active=active;
    if(changed) { [_tableView reloadData]; _cardHeight.constant=MIN(MAX(64,self.view.bounds.size.height-48),64+_active.count*64); }
    else for(NSIndexPath *index in _tableView.indexPathsForVisibleRows) {
        SDRow *row=(SDRow *)[_tableView cellForRowAtIndexPath:index]; if([row isKindOfClass:SDRow.class] && !row.slider.tracking) [self configure:row index:index];
    }
}
- (void)masterChanged:(UISlider *)slider { if(![SDMasterVolume setLevel:slider.value]) { float level=[SDMasterVolume level]; if(level>=0) slider.value=level; } }
- (void)save {
    NSMutableDictionary *changes=[NSMutableDictionary new];
    for(NSString *key in _prefs) {
        if([key isEqual:@"apps"]) {
            NSMutableDictionary *apps=[NSMutableDictionary new];
            for(NSString *bid in _prefs[key]) {
                NSMutableDictionary *delta=[NSMutableDictionary new];
                for(NSString *field in _prefs[key][bid]) if(![_prefs[key][bid][field] isEqual:_savedPreferences[key][bid][field]]) delta[field]=_prefs[key][bid][field];
                if(delta.count) apps[bid]=delta;
            }
            if(apps.count) changes[key]=apps;
        } else if(![_prefs[key] isEqual:_savedPreferences[key]]) changes[key]=_prefs[key];
    }
    if(SDUpdatePrefs(changes,nil)) { _prefs=[SDReadPrefs() mutableCopy]; _savedPreferences=[_prefs copy]; }
}
- (void)configure:(SDRow *)row index:(NSIndexPath *)index {
    NSDictionary *app=_active[index.row]; NSString *bid=app[@"bundleID"],*name=app[@"name"] ?: bid;
    NSDictionary *entry=_prefs[@"apps"][bid] ?: @{};
    row.bundleID=bid; row.appIcon.image=[UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:UIScreen.mainScreen.scale] ?: [UIImage systemImageNamed:@"waveform"];
    row.slider.value=[entry[@"muted"] boolValue]?0:(entry[@"gain"]?[entry[@"gain"] floatValue]:1);
    row.slider.enabled=[app[@"controllable"] boolValue]; row.slider.accessibilityLabel=[NSString stringWithFormat:@"%@ volume",name];
    row.slider.accessibilityValue=row.slider.value<=0?@"Muted":[NSString stringWithFormat:@"%.0f percent",row.slider.value*100];
    __weak typeof(self) weak=self;
    row.change=^(NSString *identifier,float value,BOOL muteChange,BOOL muted) {
        SDController *controller=weak; if(!controller) return;
        NSMutableDictionary *apps=[controller.prefs[@"apps"] mutableCopy] ?: [NSMutableDictionary new];
        NSMutableDictionary *updated=[apps[identifier] mutableCopy] ?: [NSMutableDictionary new];
        updated[@"name"]=name; updated[@"gain"]=@(value); updated[@"muted"]=@NO; apps[identifier]=updated; controller.prefs[@"apps"]=apps;
        int token; if(!notify_register_check(SDGainName(identifier).UTF8String,&token)) { notify_set_state(token,SDConfig(controller.prefs,updated)); notify_post(SDGainName(identifier).UTF8String); notify_cancel(token); }
        [controller.saveTimer invalidate]; controller.saveTimer=[NSTimer scheduledTimerWithTimeInterval:.2 repeats:NO block:^(NSTimer *timer){ [weak save]; weak.saveTimer=nil; }];
    };
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 1; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return _active.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    SDRow *row=[table dequeueReusableCellWithIdentifier:@"app" forIndexPath:index]; [self configure:row index:index]; return row;
}
@end
@interface SDDelegate:UIResponder<UIApplicationDelegate>
@property(strong,nonatomic) UIWindow *window;
@end
@implementation SDDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options { return YES; }
@end
@interface SDSceneDelegate:UIResponder<UIWindowSceneDelegate>
@property(strong,nonatomic) UIWindow *window;
@end
@implementation SDSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController=[SDController new];
    self.window.overrideUserInterfaceStyle=[SDReadPrefs()[@"appearance"] integerValue];
    [self.window makeKeyAndVisible];
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(SDDelegate.class)); } }
