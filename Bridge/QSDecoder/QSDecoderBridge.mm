#import "QSDecoderBridge.h"

#include "QSDecoderFallback.hpp"

@interface QSDecoderBridge () {
    QSDecoderFallback *_decoder;
}
@end

@implementation QSDecoderBridge

- (instancetype)initWithSampleRate:(int32_t)sampleRate {
    self = [super init];
    if (self) {
        _decoder = new QSDecoderFallback(sampleRate);
    }
    return self;
}

- (void)dealloc {
    delete _decoder;
    _decoder = nullptr;
}

- (void)decodeLeft:(const float *)left
             right:(const float *)right
        frameCount:(uint32_t)frameCount
         frontLeft:(float *)frontLeft
        frontRight:(float *)frontRight
          rearLeft:(float *)rearLeft
         rearRight:(float *)rearRight {
    _decoder->decode(left, right, frameCount, frontLeft, frontRight, rearLeft, rearRight);
}

@end
