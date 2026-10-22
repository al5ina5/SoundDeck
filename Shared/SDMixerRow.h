#import <UIKit/UIKit.h>
@interface SDRow : UITableViewCell
@property(strong) UILabel *nameLabel,*statusLabel,*valueLabel;
@property(strong) UIImageView *appIcon;
@property(strong) UISlider *slider;
@property(strong) UIButton *mute;
@property(copy) NSString *bundleID;
@property(copy) void (^change)(NSString *,float,BOOL,BOOL);
@end
