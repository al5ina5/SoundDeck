#import <UIKit/UIKit.h>
int main(int argc,char **argv) { @autoreleasepool {
    if(argc!=2) return 2;
    UIGraphicsImageRendererFormat *f=[UIGraphicsImageRendererFormat defaultFormat]; f.scale=1; f.opaque=YES;
    NSArray *sizes=@[@120,@152,@167,@180,@1024];
    for(NSNumber *size in sizes) {
        CGFloat s=size.doubleValue;
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(s,s) format:f];
        UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx){
            CGContextRef c=ctx.CGContext; CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
            CGFloat colors[]={.065,.09,.20,1,.22,.25,.57,1}; CGFloat locations[]={0,1};
            CGGradientRef gradient=CGGradientCreateWithColorComponents(cs,colors,locations,2);
            CGContextDrawLinearGradient(c,gradient,CGPointZero,CGPointMake(s,s),0); CGGradientRelease(gradient); CGColorSpaceRelease(cs);
            CGFloat heights[]={.25,.50,.34}; CGFloat centers[]={.42,.61,.48};
            for(int i=0;i<3;i++) {
                CGFloat x=s*(.29+i*.21);
                CGContextSetRGBStrokeColor(c,.72,.80,1,.25); CGContextSetLineWidth(c,s*.025); CGContextSetLineCap(c,kCGLineCapRound);
                CGContextMoveToPoint(c,x,s*.23); CGContextAddLineToPoint(c,x,s*.77); CGContextStrokePath(c);
                CGContextSetRGBStrokeColor(c,.65,.84,1,1); CGContextSetLineWidth(c,s*.065);
                CGContextMoveToPoint(c,x,s*(.77-heights[i])); CGContextAddLineToPoint(c,x,s*.77); CGContextStrokePath(c);
                CGRect knob=CGRectMake(x-s*.065,s*centers[i]-s*.045,s*.13,s*.09);
                [[UIColor colorWithRed:.96 green:.98 blue:1 alpha:1] setFill]; [[UIBezierPath bezierPathWithRoundedRect:knob cornerRadius:s*.025] fill];
            }
        }];
        NSString *name=@{@120:@"Icon60@2x.png",@152:@"Icon76@2x.png",@167:@"Icon83.5@2x.png",@180:@"Icon60@3x.png",@1024:@"Icon1024.png"}[size];
        [UIImagePNGRepresentation(image) writeToFile:[@(argv[1]) stringByAppendingPathComponent:name] atomically:YES];
    } return 0;
} }
