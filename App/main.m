#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import "../Shared/SDProtocol.h"
#import "SDMasterVolume.h"
@interface UIImage (SDPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(CGFloat)scale;
@end
@interface SDRow : UITableViewCell
@property(strong) UILabel *nameLabel,*statusLabel,*valueLabel;
@property(strong) UIImageView *appIcon;
@property(strong) UISlider *slider;
@property(strong) UIButton *mute;
@property(copy) NSString *bundleID;
@property(copy) void (^change)(NSString *,float,BOOL,BOOL);
@end
@implementation SDRow
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if((self=[super initWithStyle:style reuseIdentifier:identifier])) {
        self.selectionStyle=UITableViewCellSelectionStyleNone;
        _appIcon=[UIImageView new]; _appIcon.layer.cornerRadius=12; _appIcon.clipsToBounds=YES;
        _appIcon.contentMode=UIViewContentModeScaleAspectFit; _appIcon.tintColor=UIColor.systemIndigoColor;
        _nameLabel=[UILabel new]; _nameLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; _nameLabel.adjustsFontForContentSizeCategory=YES;
        _statusLabel=[UILabel new]; _statusLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; _statusLabel.textColor=UIColor.secondaryLabelColor;
        _statusLabel.adjustsFontForContentSizeCategory=YES; _statusLabel.numberOfLines=2;
        _valueLabel=[UILabel new]; _valueLabel.font=[UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightMedium]]; _valueLabel.adjustsFontForContentSizeCategory=YES;
        [_valueLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        _slider=[UISlider new]; _slider.minimumValue=0; _slider.maximumValue=1; _slider.tintColor=UIColor.systemIndigoColor;
        [_slider addTarget:self action:@selector(slide:) forControlEvents:UIControlEventValueChanged];
        _mute=[UIButton buttonWithType:UIButtonTypeSystem]; [_mute addTarget:self action:@selector(muteTap) forControlEvents:UIControlEventTouchUpInside];
        UIStackView *titles=[[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel,_statusLabel]]; titles.axis=UILayoutConstraintAxisVertical; titles.spacing=4;
        UIStackView *top=[[UIStackView alloc] initWithArrangedSubviews:@[_appIcon,titles,_valueLabel]]; top.spacing=14; top.alignment=UIStackViewAlignmentCenter;
        UIStackView *bottom=[[UIStackView alloc] initWithArrangedSubviews:@[_slider,_mute]]; bottom.spacing=12; bottom.alignment=UIStackViewAlignmentCenter;
        UIStackView *all=[[UIStackView alloc] initWithArrangedSubviews:@[top,bottom]]; all.axis=UILayoutConstraintAxisVertical; all.spacing=12; all.translatesAutoresizingMaskIntoConstraints=NO;
        [self.contentView addSubview:all];
        [NSLayoutConstraint activateConstraints:@[[all.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:18],[all.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-14],[all.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],[all.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],[_appIcon.widthAnchor constraintEqualToConstant:44],[_appIcon.heightAnchor constraintEqualToConstant:44],[_mute.widthAnchor constraintEqualToConstant:48],[_mute.heightAnchor constraintEqualToConstant:44]]];
    } return self;
}
- (void)slide:(UISlider *)s { _valueLabel.text=[NSString stringWithFormat:@"%.0f%%",s.value*100]; if(_change) _change(_bundleID,s.value,NO,NO); }
- (void)muteTap { if(_change) _change(_bundleID,0,YES,!_mute.selected); }
@end
@interface SDController : UITableViewController
@property(strong) NSDictionary *status;
@property(strong) NSMutableDictionary *prefs;
@property(strong) NSDictionary *savedPreferences;
@property(strong) NSArray *active,*saved;
@property(strong) NSTimer *timer;
@property(strong) NSTimer *saveTimer;
@property(strong) UILabel *routeLabel,*healthLabel;
@property(strong) MPVolumeView *master;
@property(strong) UISlider *masterSlider;
@end
@implementation SDController
- (void)capture {
    UIWindow *window=self.view.window; if(!window) return;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){ [window.layer renderInContext:context.CGContext]; }];
    [UIImagePNGRepresentation(image) writeToFile:SD_DIR @"/capture.png" atomically:YES];
    NSMutableArray *rows=[NSMutableArray new];
    for(UITableViewCell *cell in self.tableView.visibleCells) if([cell isKindOfClass:SDRow.class]) {
        SDRow *row=(SDRow *)cell;
        [rows addObject:@{@"bundleID":row.bundleID ?: @"",@"gain":@(row.slider.value),@"muted":@(row.mute.selected),
          @"sliderAccessible":@(row.slider.accessibilityLabel.length>0),@"muteAccessible":@(row.mute.accessibilityLabel.length>0),
          @"iconPresent":@(row.appIcon.image!=nil),@"touchTargetHeight":@(row.mute.bounds.size.height),@"ambiguous":@(row.contentView.hasAmbiguousLayout)}];
    }
    [@{@"phase":@"captured",@"state":@(UIApplication.sharedApplication.applicationState),@"width":@(window.bounds.size.width),@"height":@(window.bounds.size.height),@"style":@(window.traitCollection.userInterfaceStyle),@"rows":rows} writeToFile:SD_DIR @"/ui-diagnostics.plist" atomically:YES];
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"SoundDeck"; self.navigationController.navigationBar.prefersLargeTitles=YES;
    self.view.tintColor=UIColor.systemIndigoColor;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addApp)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel=@"Add application to SoundDeck";
    self.tableView.cellLayoutMarginsFollowReadableWidth=YES; self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=136;
    [self.tableView registerClass:SDRow.class forCellReuseIdentifier:@"app"];
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,600,154)];
    UIVisualEffectView *material=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    material.layer.cornerRadius=20; material.clipsToBounds=YES; material.translatesAutoresizingMaskIntoConstraints=NO; [header addSubview:material];
    _routeLabel=[UILabel new]; _routeLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; _routeLabel.adjustsFontForContentSizeCategory=YES;
    _healthLabel=[UILabel new]; _healthLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; _healthLabel.textColor=UIColor.secondaryLabelColor; _healthLabel.numberOfLines=2; _healthLabel.adjustsFontForContentSizeCategory=YES;
    _master=[[MPVolumeView alloc] initWithFrame:CGRectZero]; _master.showsRouteButton=YES; _master.accessibilityLabel=@"System master volume";
    _master.tintColor=UIColor.systemIndigoColor;
    _masterSlider=[UISlider new]; _masterSlider.tintColor=UIColor.systemIndigoColor; _masterSlider.accessibilityLabel=@"System media master volume";
    [_masterSlider addTarget:self action:@selector(masterChanged:) forControlEvents:UIControlEventValueChanged];
    BOOL direct=[SDMasterVolume available]; _masterSlider.hidden=!direct; _master.showsVolumeSlider=!direct;
    UIStackView *masterRow=[[UIStackView alloc] initWithArrangedSubviews:@[_masterSlider,_master]]; masterRow.spacing=12; masterRow.alignment=UIStackViewAlignmentCenter;
    if(direct) [_master.widthAnchor constraintEqualToConstant:44].active=YES;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[_routeLabel,_healthLabel,masterRow]]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=10; stack.translatesAutoresizingMaskIntoConstraints=NO; [material.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[material.leadingAnchor constraintEqualToAnchor:header.readableContentGuide.leadingAnchor],[material.trailingAnchor constraintEqualToAnchor:header.readableContentGuide.trailingAnchor],[material.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],[material.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8],[stack.leadingAnchor constraintEqualToAnchor:material.contentView.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:material.contentView.trailingAnchor constant:-20],[stack.topAnchor constraintEqualToAnchor:material.contentView.topAnchor constant:18],[stack.bottomAnchor constraintEqualToAnchor:material.contentView.bottomAnchor constant:-16],[_master.heightAnchor constraintEqualToConstant:32]]];
    self.tableView.tableHeaderView=header;
    [self refresh];
    int captureToken; __weak typeof(self) captureSelf=self;
    notify_register_dispatch("com.alsinas.sounddeck.capture",&captureToken,dispatch_get_main_queue(),^(int token){
        [captureSelf capture];
    });
#ifdef SD_TESTING
    for(NSString *command in @[@"sliders",@"mute",@"unmute",@"master",@"portrait",@"landscape"]) {
        int testToken;
        NSString *name=[@"com.alsinas.sounddeck.test-ui." stringByAppendingString:command];
        notify_register_dispatch(name.UTF8String,&testToken,dispatch_get_main_queue(),^(int token){
            SDController *s=captureSelf;
            if([command isEqual:@"master"]) {
                UISlider *slider=s.masterSlider; if(slider.hidden) return;
                float initial=[SDMasterVolume level]; if(initial<0) return;
                float requested=initial*.5f;
                slider.value=requested; [slider sendActionsForControlEvents:UIControlEventValueChanged];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                    float changed=AVAudioSession.sharedInstance.outputVolume;
                    slider.value=initial; [slider sendActionsForControlEvents:UIControlEventValueChanged];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                        [@{@"initial":@(initial),@"requested":@(requested),@"changed":@(changed),@"restored":@(AVAudioSession.sharedInstance.outputVolume),@"restoredNative":@([SDMasterVolume level]),@"method":@"UIKit slider action to AVSystemController; measured with AVAudioSession.outputVolume"} writeToFile:SD_DIR @"/master-test.plist" atomically:YES];
                    });
                }); return;
            }
            if([command isEqual:@"portrait"] || [command isEqual:@"landscape"]) {
                if(@available(iOS 16.0,*)) {
                    UIWindowSceneGeometryPreferencesIOS *geometry=[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:[command isEqual:@"portrait"]?UIInterfaceOrientationMaskPortrait:UIInterfaceOrientationMaskLandscapeLeft];
                    [s.view.window.windowScene requestGeometryUpdateWithPreferences:geometry errorHandler:^(NSError *error){ [@{@"error":error.localizedDescription} writeToFile:SD_DIR @"/rotation-test.plist" atomically:YES]; }];
                } return;
            }
            for(UITableViewCell *cell in s.tableView.visibleCells) if([cell isKindOfClass:SDRow.class]) {
                SDRow *row=(SDRow *)cell;
                if(![row.bundleID hasSuffix:@"sounddeck.toneA"] && ![row.bundleID hasSuffix:@"sounddeck.toneB"]) continue;
                if([command isEqual:@"sliders"]) { row.slider.value=[row.bundleID hasSuffix:@"toneA"]?.2:.8; [row.slider sendActionsForControlEvents:UIControlEventValueChanged]; }
                else if([row.bundleID hasSuffix:@"toneA"] && row.mute.selected==[command isEqual:@"unmute"]) [row.mute sendActionsForControlEvents:UIControlEventTouchUpInside];
            }
        });
    }
#endif
    __weak typeof(self) weak=self;
    _timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){ [weak refresh]; }];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:AVAudioSessionRouteChangeNotification object:nil];
}
- (void)dealloc { [_timer invalidate]; [_saveTimer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header=self.tableView.tableHeaderView; if(!header) return;
    CGFloat width=self.tableView.bounds.size.width;
    CGSize fit=[header systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGFloat height=MAX(140,ceil(fit.height));
    if(fabs(header.bounds.size.height-height)>.5) { CGRect frame=header.frame; frame.size.height=height; header.frame=frame; self.tableView.tableHeaderView=header; }
}
- (void)refresh {
    if(!_saveTimer) { _prefs=[SDReadPrefs() mutableCopy]; _savedPreferences=[_prefs copy]; }
    self.view.window.overrideUserInterfaceStyle=[_prefs[@"appearance"] integerValue];
    float master=[SDMasterVolume level];
    if(master>=0 && !_masterSlider.tracking) { _masterSlider.value=master; _masterSlider.accessibilityValue=[NSString stringWithFormat:@"%.0f percent",master*100]; }
    _status=[NSDictionary dictionaryWithContentsOfFile:SD_STATUS] ?: @{};
    BOOL fresh=NSDate.date.timeIntervalSince1970-[_status[@"timestamp"] doubleValue]<4;
    NSMutableArray *active=[NSMutableArray new]; NSMutableSet *live=[NSMutableSet new];
    for(NSDictionary *c in fresh?_status[@"clients"]:@[]) if([c[@"active"] boolValue]) { [active addObject:c]; [live addObject:c[@"bundleID"]]; }
    NSMutableArray *saved=[NSMutableArray new];
    for(NSString *bid in [_prefs[@"apps"] allKeys]) if(![live containsObject:bid]) [saved addObject:@{@"bundleID":bid,@"name":_prefs[@"apps"][bid][@"name"] ?: bid}];
    [saved sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];
    NSArray *oldKeys=[_active valueForKey:@"bundleID"],*newKeys=[active valueForKey:@"bundleID"];
    BOOL changed=![oldKeys isEqual:newKeys] || ![[_saved valueForKey:@"bundleID"] isEqual:[saved valueForKey:@"bundleID"]];
    _active=active; _saved=saved;
    NSString *route=AVAudioSession.sharedInstance.currentRoute.outputs.firstObject.portName ?: @"System audio output";
    _routeLabel.text=[NSString stringWithFormat:@"%@ · Master volume",route];
    _healthLabel.text=!fresh?@"Backend unavailable · Enrolled clients automatically bypass after 5 seconds.":([_prefs[@"disabled"] boolValue]?@"SoundDeck is bypassed · Original audio levels restored":@"Experimental · Only enrolled, compatible playback paths are controlled");
    if(changed) [self.tableView reloadData];
    else for(NSIndexPath *index in self.tableView.indexPathsForVisibleRows) if(index.section<2) {
        SDRow *cell=[self.tableView cellForRowAtIndexPath:index]; if([cell isKindOfClass:SDRow.class] && !cell.slider.tracking) [self configure:cell index:index];
    }
}
- (void)masterChanged:(UISlider *)slider {
    if(![SDMasterVolume setLevel:slider.value]) { float level=[SDMasterVolume level]; if(level>=0) slider.value=level; }
}
- (void)save {
    NSError *error=nil;
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
    if(!SDUpdatePrefs(changes,&error)) [self alert:@"Could not save" text:error.localizedDescription];
    else { _prefs=[SDReadPrefs() mutableCopy]; _savedPreferences=[_prefs copy]; }
}
- (void)alert:(NSString *)title text:(NSString *)text {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)configure:(SDRow *)row index:(NSIndexPath *)index {
    NSDictionary *c=(index.section==0?_active:_saved)[index.row]; NSString *bid=c[@"bundleID"];
    NSDictionary *a=_prefs[@"apps"][bid] ?: @{};
    row.bundleID=bid; row.nameLabel.text=c[@"name"] ?: bid;
    BOOL active=[c[@"active"] boolValue];
    row.statusLabel.text=active?[NSString stringWithFormat:@"Playing · %@%@",c[@"path"],[c[@"metered"] boolValue]?@" · PCM measured":@" · Not signal-verified"]:@"Saved · Restart after enrolling · Compatibility not verified";
    row.slider.value=a[@"gain"]?[a[@"gain"] floatValue]:1;
    row.slider.accessibilityLabel=[NSString stringWithFormat:@"%@ volume",row.nameLabel.text];
    row.slider.accessibilityValue=[NSString stringWithFormat:@"%.0f percent",row.slider.value*100];
    row.valueLabel.text=[NSString stringWithFormat:@"%.0f%%",row.slider.value*100];
    row.mute.selected=[a[@"muted"] boolValue];
    [row.mute setImage:[UIImage systemImageNamed:row.mute.selected?@"speaker.slash.fill":@"speaker.wave.2.fill"] forState:UIControlStateNormal];
    row.mute.accessibilityLabel=[NSString stringWithFormat:@"%@ %@",row.mute.selected?@"Unmute":@"Mute",row.nameLabel.text];
    row.appIcon.image=[UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:UIScreen.mainScreen.scale] ?: [UIImage systemImageNamed:@"waveform"];
    __weak typeof(self) weak=self;
    __weak SDRow *weakRow=row;
    row.change=^(NSString *identifier,float gain,BOOL muteChange,BOOL muted) {
        SDController *self=weak; if(!self) return;
        NSMutableDictionary *apps=[self.prefs[@"apps"] mutableCopy] ?: [NSMutableDictionary new];
        NSMutableDictionary *entry=[apps[identifier] mutableCopy] ?: [NSMutableDictionary new];
        entry[@"name"]=c[@"name"] ?: identifier;
        entry[muteChange?@"muted":@"gain"]=muteChange?@(muted):@(gain);
        apps[identifier]=entry; self.prefs[@"apps"]=apps;
        // Live notifyd gain, with debounced persistence; no disk write for every slider frame.
        int token; if(!notify_register_check(SDGainName(identifier).UTF8String,&token)) {
            notify_set_state(token,SDConfig(self.prefs,entry)); notify_post(SDGainName(identifier).UTF8String); notify_cancel(token);
        }
        [self.saveTimer invalidate];
        self.saveTimer=[NSTimer scheduledTimerWithTimeInterval:.2 repeats:NO block:^(NSTimer *timer){ [weak save]; weak.saveTimer=nil; }];
        if(muteChange) { [self configure:weakRow index:index]; UISelectionFeedbackGenerator *h=[UISelectionFeedbackGenerator new]; [h selectionChanged]; }
    };
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 3; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section==0?MAX(1,_active.count):(section==1?MAX(1,_saved.count):6); }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { return @[@"Active Audio",@"Saved Applications",@"Settings & Diagnostics"][section]; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if(section==0) return @"Activity comes from actual render callbacks or player state. PCM measurements are not microphone recordings.";
    if(section==1) return @"Use + to enroll an app, then restart that app. Enrollment does not guarantee compatibility. Recording and call audio are excluded.";
    return @"SoundDeck 0.1 · Experimental\nDucking is not implemented. Bluetooth, AirPlay, DRM and third-party app compatibility need device validation.";
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    NSArray *items=index.section==0?_active:_saved;
    if(index.section<2 && items.count) { SDRow *row=[table dequeueReusableCellWithIdentifier:@"app" forIndexPath:index]; [self configure:row index:index]; return row; }
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; cell.textLabel.adjustsFontForContentSizeCategory=YES;
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; cell.detailTextLabel.numberOfLines=0;
    if(index.section<2) {
        cell.textLabel.text=index.section==0?@"No compatible audio is playing":@"Your mix, remembered";
        cell.detailTextLabel.text=index.section==0?@"Start an enrolled app or a SoundDeck test signal.":@"Enroll an application to keep its volume between launches.";
        cell.imageView.image=[UIImage systemImageNamed:index.section==0?@"waveform":@"slider.horizontal.3"];
        cell.selectionStyle=UITableViewCellSelectionStyleNone; return cell;
    }
    cell.textLabel.text=@[@"Allow simultaneous playback",@"Bypass SoundDeck",@"Appearance",@"Compatibility & diagnostics",@"Reset all volumes",@"Emergency recovery"][index.row];
    cell.imageView.image=[UIImage systemImageNamed:@[@"square.stack.3d.up",@"power",@"circle.lefthalf.filled",@"stethoscope",@"arrow.counterclockwise",@"lifepreserver"][index.row]];
    if(index.row<2) {
        UISwitch *s=[UISwitch new]; s.tag=index.row; s.on=[_prefs[index.row==0?@"mixing":@"disabled"] boolValue]; [s addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView=s;
        s.accessibilityLabel=cell.textLabel.text;
        cell.detailTextLabel.text=index.row==0?@"Applied when compatible playback sessions activate. Restart playback after changing.":@"Restores unity gain immediately. Disable before uninstalling.";
        cell.selectionStyle=UITableViewCellSelectionStyleNone;
    } else cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)toggle:(UISwitch *)s { _prefs[s.tag==0?@"mixing":@"disabled"]=@(s.on); [self save]; }
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES]; if(index.section!=2) return;
    if(index.row==2) {
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Appearance" message:nil preferredStyle:UIAlertControllerStyleAlert];
        NSArray *names=@[@"System",@"Light",@"Dark"];
        for(NSInteger i=0;i<3;i++) [a addAction:[UIAlertAction actionWithTitle:names[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ self.view.window.overrideUserInterfaceStyle=i; self.prefs[@"appearance"]=@(i); [self save]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
    } else if(index.row==3) {
        [self alert:@"Compatibility & diagnostics" text:[NSString stringWithFormat:@"Backend: %@\nLast update: %@\nClients: %lu\n\nVerified path: direct RemoteIO PCM (Float32). AVPlayer uses per-object gain; real-world compatibility is unverified. AudioQueue, AVAudioEngine graphs, WebKit subprocesses, protected media, calls and recording are not supported. Mixed-framework apps may bypass control. No universal support is claimed.\n\nDiagnostics contain bundle IDs, gain and numeric PCM RMS only. No recordings or content metadata.",_status[@"version"] ?: @"unavailable",_status[@"timestamp"] ?: @"none",(unsigned long)[_status[@"clients"] count]]];
    } else if(index.row==4) {
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Reset all volumes?" message:@"Saved gains and mute states return to defaults. Enrolled apps stay enrolled." preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
            NSMutableDictionary *apps=[self.prefs[@"apps"] mutableCopy];
            for(NSString *bid in apps.allKeys) { NSMutableDictionary *entry=[apps[bid] mutableCopy]; entry[@"gain"]=@1; entry[@"muted"]=@NO; apps[bid]=entry; }
            self.prefs[@"apps"]=apps ?: @{}; [self save]; [self.tableView reloadData];
        }]]; [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
    } else if(index.row==5) [self alert:@"Emergency recovery" text:@"In NewTerm, run:\nsdctl disable\n\nIf the service is unavailable, rename SoundDeck.plist in /var/jb/Library/MobileSubstrate/DynamicLibraries, then restart only affected apps.\n\nUninstall:\nsudo apt remove com.alsinas.sounddeck\n\nNo SpringBoard or audio-daemon injection is used."];
}
- (void)addApp {
    Class workspace=NSClassFromString(@"LSApplicationWorkspace");
    id ws=((id(*)(id,SEL))objc_msgSend)(workspace,NSSelectorFromString(@"defaultWorkspace"));
    NSArray *proxies=((id(*)(id,SEL))objc_msgSend)(ws,NSSelectorFromString(@"allApplications"));
    NSMutableArray *entries=[NSMutableArray new];
    for(id proxy in proxies) {
        NSString *bid=[proxy valueForKey:@"applicationIdentifier"],*name=[proxy valueForKey:@"localizedName"];
        NSString *type=[proxy valueForKey:@"applicationType"];
        if(!bid || [bid isEqual:@"com.alsinas.sounddeck"] || [bid isEqual:@"com.apple.springboard"]) continue;
        if([type isEqual:@"User"] || [@[@"com.apple.Music",@"com.apple.mobilesafari",@"com.alsinas.sounddeck.toneA",@"com.alsinas.sounddeck.toneB"] containsObject:bid]) [entries addObject:@{@"bid":bid,@"name":name ?: bid}];
    }
    [entries sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Enroll Application" message:@"Experimental. Restart the chosen app after enrolling. Do not enroll communication, banking, or safety-critical apps." preferredStyle:UIAlertControllerStyleActionSheet];
    for(NSDictionary *entry in entries) [a addAction:[UIAlertAction actionWithTitle:entry[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSMutableDictionary *apps=[self.prefs[@"apps"] mutableCopy] ?: [NSMutableDictionary new];
        NSMutableDictionary *p=[apps[entry[@"bid"]] mutableCopy] ?: [NSMutableDictionary new];
        p[@"name"]=entry[@"name"]; p[@"enrolled"]=@YES; apps[entry[@"bid"]]=p; self.prefs[@"apps"]=apps;
        [self save]; [self refresh]; [self alert:@"Application enrolled" text:@"Restart this application to load SoundDeck. Gain control works only if it uses a supported audio path."];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem; [self presentViewController:a animated:YES completion:nil];
}
@end
@interface SDDelegate:UIResponder<UIApplicationDelegate>
@property(strong,nonatomic) UIWindow *window;
@end
@implementation SDDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    return YES;
}
@end
@interface SDSceneDelegate:UIResponder<UIWindowSceneDelegate>
@property(strong,nonatomic) UIWindow *window;
@end
@implementation SDSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController=[[UINavigationController alloc] initWithRootViewController:[[SDController alloc] initWithStyle:UITableViewStyleInsetGrouped]];
    self.window.overrideUserInterfaceStyle=[SDReadPrefs()[@"appearance"] integerValue];
    [self.window makeKeyAndVisible];
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(SDDelegate.class)); } }
