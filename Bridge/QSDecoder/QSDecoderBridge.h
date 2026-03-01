#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface QSDecoderBridge : NSObject

- (instancetype)initWithSampleRate:(int32_t)sampleRate;
- (void)decodeLeft:(const float *)left
             right:(const float *)right
        frameCount:(uint32_t)frameCount
         frontLeft:(float *)frontLeft
        frontRight:(float *)frontRight
          rearLeft:(float *)rearLeft
         rearRight:(float *)rearRight;

@end

NS_ASSUME_NONNULL_END
