#import "SDMixerRow.h"
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
