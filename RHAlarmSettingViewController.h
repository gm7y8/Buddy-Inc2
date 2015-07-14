

#import <UIKit/UIKit.h>

@class RHAlarmSettingViewController;

@protocol RHAlarmSettinViewControllerDelegate <NSObject>

- (void)alarmSettingViewControllerCancelled:(RHAlarmSettingViewController *)alarmSettingController;
- (void)alarmSettingViewController:(RHAlarmSettingViewController *)alarmSettingController doneWithDuration:(NSTimeInterval)duration;

@end

@interface RHAlarmSettingViewController : UIViewController
@property (nonatomic, weak)id<RHAlarmSettinViewControllerDelegate> delegate;

@end
