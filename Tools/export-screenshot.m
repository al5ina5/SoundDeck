#import <UIKit/UIKit.h>
int main(int argc,char **argv) { @autoreleasepool {
    if(argc!=3) return 2;
    UIImage *image=[UIImage imageWithContentsOfFile:@(argv[1])]; if(!image) return 1;
    // Crop only: keep actual pixels; omit saved application rows from public documentation.
    CGImageRef cropped=CGImageCreateWithImageInRect(image.CGImage,CGRectMake(0,0,CGImageGetWidth(image.CGImage),MIN(1240,CGImageGetHeight(image.CGImage))));
    BOOL ok=[UIImagePNGRepresentation([UIImage imageWithCGImage:cropped]) writeToFile:@(argv[2]) atomically:YES]; CGImageRelease(cropped);
    return ok?0:1;
} }
