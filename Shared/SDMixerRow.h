#import <UIKit/UIKit.h>
@interface SDRow : UITableViewCell
@property(strong) UIImageView *appIcon;
@property(strong) UISlider *slider;
@property(copy) NSString *bundleID;
@property(copy) void (^change)(NSString *,float,BOOL,BOOL);
@end
