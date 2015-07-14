

#import <UIKit/UIKit.h>
#import <RMCore/RMCore.h>
#import <RMCharacter/RMCharacter.h>
#import <opencv2/opencv.hpp>
@interface RHViewController : UIViewController

@property (nonatomic, strong) RMCoreRobotRomo3 *Romo3;

- (void)addGestureRecognizers;


@end
