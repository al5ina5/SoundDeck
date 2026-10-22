#import "SDMixerRow.h"
@implementation SDRow
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if((self=[super initWithStyle:style reuseIdentifier:identifier])) {
        self.selectionStyle=UITableViewCellSelectionStyleNone;
        self.backgroundColor=UIColor.clearColor; self.contentView.backgroundColor=UIColor.clearColor;
        _appIcon=[UIImageView new]; _appIcon.layer.cornerRadius=8; _appIcon.clipsToBounds=YES;
        _appIcon.contentMode=UIViewContentModeScaleAspectFit; _appIcon.tintColor=UIColor.labelColor;
        _appIcon.isAccessibilityElement=NO;
        _slider=[UISlider new]; _slider.minimumValue=0; _slider.maximumValue=1; _slider.tintColor=UIColor.systemIndigoColor;
        _slider.accessibilityTraits=UIAccessibilityTraitAdjustable;
        [_slider addTarget:self action:@selector(slide:) forControlEvents:UIControlEventValueChanged];
        UIStackView *line=[[UIStackView alloc] initWithArrangedSubviews:@[_appIcon,_slider]];
        line.axis=UILayoutConstraintAxisHorizontal; line.alignment=UIStackViewAlignmentCenter; line.spacing=14;
        line.translatesAutoresizingMaskIntoConstraints=NO; [self.contentView addSubview:line];
        [NSLayoutConstraint activateConstraints:@[[line.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18],
            [line.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18],
            [line.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [line.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
            [_appIcon.widthAnchor constraintEqualToConstant:36],[_appIcon.heightAnchor constraintEqualToConstant:36]]];
    } return self;
}
- (void)slide:(UISlider *)s {
    s.accessibilityValue=s.value<=0?@"Muted":[NSString stringWithFormat:@"%.0f percent",s.value*100];
    if(_change) _change(_bundleID,s.value,NO,NO);
}
@end
