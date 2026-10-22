#import <Foundation/Foundation.h>
@interface SDMasterVolume:NSObject
+ (BOOL)available;
+ (float)level;
+ (BOOL)setLevel:(float)level;
@end
