
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <opencv2/opencv.hpp>

@class RHFaceDetector;

@protocol RHFaceDetectorDelegate <NSObject>

- (void)faceDetector:(RHFaceDetector *)faceDetector didDetectFaceAtRegion:(CGRect)rect;

- (void)faceDetectordidNotDetectFace:(RHFaceDetector *)faceDetector;

@end
@interface RHFaceDetector : NSObject <UIGestureRecognizerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

- (void)setupAVCapture;
- (void)teardownAVCapture;

@property(nonatomic, weak)id<RHFaceDetectorDelegate> delegate;


@end
