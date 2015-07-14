

#import "RHViewController.h"
#import <RMCore/RMCore.h>
#import <RMCharacter/RMCharacter.h>
#import "RHAlarmSettingViewController.h"
#import "RHTwitter.h"
#import "RHFaceDetector.h"
#import "RHColorDetector.h"
#import <AVFoundation/AVFoundation.h>
#import "GCDAsyncSocket.h"
#include <ifaddrs.h>
#include <arpa/inet.h>

#define WELCOME_MSG  0
#define ECHO_MSG     1
#define WARNING_MSG  2

#define READ_TIMEOUT 15.0
#define READ_TIMEOUT_EXTENSION 10.0

#define FORMAT(format, ...) [NSString stringWithFormat:(format), ##__VA_ARGS__]
#define PORT 1234


@interface RHViewController () <RMCoreDelegate, RHAlarmSettinViewControllerDelegate, AVSpeechSynthesizerDelegate, RHColorDetectorProtocol>{
    dispatch_queue_t socketQueue;
    NSMutableArray *connectedSockets;
    BOOL isRunning;
    GCDAsyncSocket *listenSocket;
}

@property (nonatomic, strong) RMCoreRobot<HeadTiltProtocol, DriveProtocol, LEDProtocol> *robot;
@property (nonatomic, strong) RMCharacter *romoCharacter;
@property (weak, nonatomic) IBOutlet UIView *romoView;
@property (nonatomic, strong)NSTimer *dateTimer;
@property (nonatomic, strong)NSTimer *timer;
@property (nonatomic, assign)NSUInteger tick;
@property (weak, nonatomic) IBOutlet UILabel *hourLabel;
@property (weak, nonatomic) IBOutlet UILabel *minuteLabel;
@property (weak, nonatomic) IBOutlet UILabel *secondLabel;
@property (weak, nonatomic) IBOutlet UILabel *dateLabel;

@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (weak, nonatomic) IBOutlet UIView *alarmSettingContainer;
@property (nonatomic, assign) CGRect alarmSettingContainerFrame;

@property (nonatomic, strong) NSDate *alarmDate;

@property (weak, nonatomic) IBOutlet UIButton *wakeUpButton;
@property (weak, nonatomic) IBOutlet UIButton *alarmCancelButton;
@property (weak, nonatomic) IBOutlet UIButton *alarmButton;
@property (nonatomic, strong) UIView *darkenView;

@property (nonatomic, strong) NSArray *tweets;
@property (nonatomic, strong) AVSpeechSynthesizer* speechSynthesizer;

//@property (nonatomic, strong) RHFaceDetector *faceDetector;
@property (nonatomic, strong) RHColorDetector *colorDetector;

@property (nonatomic, assign) NSUInteger tweetCount;

@property (nonatomic, assign, getter = isWakingUp) BOOL wakingUp;
@end

@implementation RHViewController
@synthesize videoCamera;

 double speed=0.3;
- (void)viewDidLoad
{
    [super viewDidLoad];
    [RMCore setDelegate:self];
    self.romoCharacter = [RMCharacter Romo];
	// Do any additional setup after loading the view, typically from a nib.
    
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(romoViewDidTap:)];
    
    UITapGestureRecognizer *tripleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTripleTap:)];
    tripleTapRecognizer.numberOfTapsRequired = 3;
    
    [self.romoView addGestureRecognizer:tapRecognizer];
    [self.romoView addGestureRecognizer:tripleTapRecognizer];
    listenSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:socketQueue];
    
    // timer
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(onTimer:) userInfo:nil repeats:YES];
    
    self.dateFormatter = [[NSDateFormatter alloc] init];
    [self.dateFormatter setDateFormat:@"yyyy/MM/dd"];
    
    self.alarmSettingContainer.hidden = NO;
    self.alarmSettingContainerFrame = self.alarmSettingContainer.frame;
    
    self.alarmSettingContainer.frame = ({
        CGRect frame = self.alarmSettingContainer.frame;
        frame = CGRectOffset(frame, 0.0f, CGRectGetHeight(frame));
        frame;
    });
    
    self.darkenView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.darkenView.userInteractionEnabled = NO;
    self.darkenView.backgroundColor = [UIColor colorWithRed:0.012 green:0.012 blue:0.075 alpha:1.000];
    self.darkenView.alpha = 0.0f;
    [self.view insertSubview:self.darkenView belowSubview:self.alarmCancelButton];
    
    
    self.speechSynthesizer = [[AVSpeechSynthesizer alloc] init];
    self.speechSynthesizer.delegate = self;

//    self.faceDetector = [[RHFaceDetector alloc] init];
//    self.faceDetector.delegate = self;
//    [self.faceDetector setupAVCapture];
    
    self.colorDetector = [[RHColorDetector alloc] init];
    self.colorDetector.delegate = self;
    
    RHTwitter *twitter = [[RHTwitter alloc] init];
    
    __weak __typeof(self) self_ = self;
    [twitter fetchTweetsWithCompletionBlock:^(NSArray *tweets) {
        NSLog(@"tweets = %@", tweets);
        self_.tweets = tweets;
    }];
}


- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"Embed"])
    {
        UINavigationController *navController = segue.destinationViewController;
        RHAlarmSettingViewController *alarmSettingViewController = [navController.viewControllers firstObject];
        alarmSettingViewController.delegate = self;
    }
}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self.romoCharacter addToSuperview:self.romoView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.romoCharacter.expression = RMCharacterExpressionExcited;

}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.romoCharacter removeFromSuperview];
    [self.colorDetector.videoCamera stop];
}

#pragma mark - Alarm

- (void)alarmSettingViewControllerCancelled:(RHAlarmSettingViewController *)alarmSettingController {
    [self hideAlarmSetting];
}

- (void)alarmSettingViewController:(RHAlarmSettingViewController *)alarmSettingController doneWithDuration:(NSTimeInterval)duration {
    
    self.alarmButton.alpha = 0.0f;
    self.alarmCancelButton.alpha = 1.0f;
    self.alarmDate = [NSDate dateWithTimeIntervalSinceNow:duration];
    [self hideAlarmSetting];
    self.romoCharacter.emotion = RMCharacterEmotionSleepy;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.romoCharacter.emotion = RMCharacterEmotionSleeping;
    });
    
    [UIView animateWithDuration:3.0f delay:0.0f options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.darkenView.alpha = 0.8;
    } completion:^(BOOL finished) {
    }];
}

- (void)wakeupAnimation {
    [UIView animateWithDuration:0.3 animations:^{
        self.alarmDate = nil;
        self.darkenView.alpha = 0.0f;
        if(self.wakingUp) {
            self.alarmCancelButton.alpha = 0.0f;
            self.alarmButton.alpha = 0.0f;
            self.wakeUpButton.alpha = 1.0f;
        } else {
            self.alarmCancelButton.alpha = 0.0f;
            self.alarmButton.alpha = 1.0f;
            self.wakeUpButton.alpha = 0.0f;
        }
    } completion:^(BOOL finished) {
        self.romoCharacter.emotion = RMCharacterEmotionHappy;
    }];
}
- (IBAction)cancelAlarmAction:(id)sender {
    [self wakeupAnimation];
}

- (IBAction)alarmSettingAction:(id)sender {
    [self showAlarmSetting];
}

-(void)showAlarmSetting {
    [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.95 initialSpringVelocity:20.0 options:kNilOptions animations:^{
        self.alarmSettingContainer.frame = self.alarmSettingContainerFrame;
    } completion:^(BOOL finished) {
        
    }];
}

- (void)hideAlarmSetting {
    [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.95 initialSpringVelocity:20.0 options:kNilOptions animations:^{
        self.alarmSettingContainer.frame = ({
            CGRect frame = self.alarmSettingContainer.frame;
            frame = CGRectOffset(frame, 0.0f, CGRectGetHeight(frame));
            frame;
        });
    } completion:^(BOOL finished) {
        
    }];
}

#pragma mark Clock
    
- (NSString *)timeStringWithTimeInteger:(NSInteger)time {
    NSString *string = [NSString stringWithFormat:@"%02d", time];
    return string;
}

- (void)updateClock {
    NSDate *date = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *comps;
    
    self.dateLabel.text = [self.dateFormatter stringFromDate:date];
    
    // 時分秒をとりだす
    comps = [calendar components:(NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit)
                        fromDate:date];
    NSInteger hour = [comps hour];
    NSInteger minute = [comps minute];
    NSInteger second = [comps second];
    
    self.hourLabel.text = [self timeStringWithTimeInteger:hour];
    self.minuteLabel.text = [self timeStringWithTimeInteger:minute];
    self.secondLabel.text = [self timeStringWithTimeInteger:second];
}

- (void)updateRomo {
    RMPoint3D point;
    if(self.tick%2 == 0) {
        point =RMPoint3DMake(-1.0, 0.0, 0.5);
    } else {
        point = RMPoint3DMake(1.0, 0.0, 0.5);
    }
    [self.romoCharacter lookAtPoint:point animated:YES];
}

- (void)speechString:(NSString *)string {
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:string];
    AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"ja-JP"];
    utterance.voice = voice;
    utterance.preUtteranceDelay = 0.2f;
    utterance.rate = 0.4;
    utterance.pitchMultiplier = 2.0f;
    
    // AVSpeechSynthesizerにAVSpeechUtteranceを設定して読んでもらう
    [self.speechSynthesizer speakUtterance:utterance];
}
- (void)beginSpeechingTweets {
    self.tweetCount = 0;
    [self speechTweet];
}

- (void)speechTweet {
    NSString* speakingText = self.tweets[self.tweetCount];
    [self speechString:speakingText];
}

- (IBAction)wakedUpAction:(id)sender {
    [self.speechSynthesizer pauseSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    self.wakingUp = NO;
    [self wakeupAnimation];
    [self.colorDetector.videoCamera stop];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    self.tweetCount++;
    if(self.tweetCount == [self.tweets count] || !self.isWakingUp) {
        return;
    }
    [self speechTweet];
}

- (void)wakeUpIfNeeded {
    if(!self.alarmDate) return;
    
    NSComparisonResult result = [[NSDate date] compare:self.alarmDate];
    
    if(result == NSOrderedDescending) {
        // wake up!!!
        self.wakingUp = YES;
        [self.colorDetector.videoCamera start];
        [self beginSpeechingTweets];
        [self wakeupAnimation];
        self.romoCharacter.emotion = RMCharacterEmotionCurious;
        self.romoCharacter.expression = RMCharacterExpressionExcited;
    }
}

- (void)onTimer:(NSTimer *)timer {
    [self updateRomo];
    [self updateClock];
    [self wakeUpIfNeeded];
    self.tick++;
}

#pragma mark Gesture Recognizer 

- (void)romoViewDidTap:(UITapGestureRecognizer *)tapRecognizer {
    if(self.alarmDate) return;
    [self.romoCharacter mumble];
}

- (void)handleTripleTap:(UITapGestureRecognizer *)tapRecognizer {
    self.alarmDate = [NSDate dateWithTimeIntervalSinceNow:5.0];
}

#pragma mark - Romo Delegate
- (void)robotDidConnect:(RMCoreRobot *)robot {
    if(robot.isDrivable && robot.isHeadTiltable && robot.isLEDEquipped) {
        self.robot = (RMCoreRobot<HeadTiltProtocol, DriveProtocol, LEDProtocol> *)robot;
        [self.robot turnByAngle:90.0 withRadius:RM_DRIVE_RADIUS_TURN_IN_PLACE completion:nil];
    }
}

- (void)robotDidDisconnect:(RMCoreRobot *)robot {
    if(robot == self.robot) {
        self.robot = nil;
    }
}
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - move Romo
#define AREA_THRESHOLD (500000)
#define AREA_THRESHOLD_WIDTH (200000)

- (void)colorDetectorDidNotDetectColor:(RHColorDetector *)colorDetector {
    if(!self.robot.isDrivable) return;
    [self.robot stopDriving];
}

- (void)colorDetector:(RHColorDetector *)colorDetector didDetectRedAtPoint:(CGPoint)point withArea:(double)area {
    NSLog(@"area = %lf, at (%f, %f)", area, point.x, point.y);
    if(!self.robot.isDrivable) return;
    if(area > AREA_THRESHOLD - AREA_THRESHOLD_WIDTH && area < AREA_THRESHOLD + AREA_THRESHOLD_WIDTH) {
        [self.robot stopDriving];
        return;
    }
    if (area > AREA_THRESHOLD) {
        self.romoCharacter.emotion = RMCharacterExpressionScared;
        [self.robot driveBackwardWithSpeed:0.8];
    } else {
        self.romoCharacter.emotion = RMCharacterExpressionSmack;
        [self.robot driveForwardWithSpeed:1.2];
    }
}

//- (void)faceDetectordidNotDetectFace:(RHFaceDetector *)faceDetector {
//    if(!self.robot.isDrivable) return;
//    [self.robot stopDriving];
//}
//
//- (void)faceDetector:(RHFaceDetector *)faceDetector didDetectFaceAtRegion:(CGRect)rect {
//    CGFloat area = CGRectGetWidth(rect) * CGRectGetHeight(rect);
//    NSLog(@"area = %f", area);
//    
//    if(!self.robot.isDrivable) return;
//    if(area > AREA_THRESHOLD - AREA_THRESHOLD_WIDTH && area < AREA_THRESHOLD + AREA_THRESHOLD_WIDTH) {
//        [self.robot stopDriving];
//        return;
//    }
//    if (area > AREA_THRESHOLD) {
//        [self.robot driveBackwardWithSpeed:0.5];
//    } else {
//        [self.robot driveForwardWithSpeed:0.5];
//    }
//}
//
//- (void)proximitySensorStateDidChange:(NSNotification *)notification
//{
//    if(!self.robot.isDrivable) return;
//    if([UIDevice currentDevice].proximityState) {
//        RMCharacterExpression expression = self.romo.expression;
//        self.romo.emotion = RMCharacterExpressionScared;;
//        [self.robot driveBackwardWithSpeed:0.5];
//        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//            [self.robot stopDriving];
//            self.romo.expression = expression;
//        });
//    }
//}

#pragma mark -
#pragma mark Socket

- (void)toggleSocketState
{
    if(!isRunning)
    {
        NSError *error = nil;
        if(![listenSocket acceptOnPort:PORT error:&error])
        {
            [self log:FORMAT(@"Error starting server: %@", error)];
            return;
        }
        
        [self log:FORMAT(@"Echo server started on port %hu", [listenSocket localPort])];
        isRunning = YES;
    }
    else
    {
        // Stop accepting connections
        [listenSocket disconnect];
        
        // Stop any client connections
        @synchronized(connectedSockets)
        {
            NSUInteger i;
            for (i = 0; i < [connectedSockets count]; i++)
            {
                // Call disconnect on the socket,
                // which will invoke the socketDidDisconnect: method,
                // which will remove the socket from the list.
                [[connectedSockets objectAtIndex:i] disconnect];
            }
        }
        
        [self log:@"Stopped Echo server"];
        isRunning = false;
    }
}

- (void)log:(NSString *)msg {
    NSLog(@"%@", msg);
}

- (NSString *)getIPAddress
{
    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if( temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            
            temp_addr = temp_addr->ifa_next;
        }
    }
    // Free memory
    freeifaddrs(interfaces);
    
    return address;
}

#pragma mark -
#pragma mark GCDAsyncSocket Delegate

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
    // This method is executed on the socketQueue (not the main thread)
    
    @synchronized(connectedSockets)
    {
        [connectedSockets addObject:newSocket];
    }
    
    NSString *host = [newSocket connectedHost];
    UInt16 port = [newSocket connectedPort];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            
            [self log:FORMAT(@"Accepted client %@:%hu", host, port)];
            
        }
    });
    
    NSString *welcomeMsg = @"Welcome to the AsyncSocket Echo Server\r\n";
    NSData *welcomeData = [welcomeMsg dataUsingEncoding:NSUTF8StringEncoding];
    
    [newSocket writeData:welcomeData withTimeout:-1 tag:WELCOME_MSG];
    
    
    [newSocket readDataWithTimeout:READ_TIMEOUT tag:0];
    newSocket.delegate = self;
    
    //    [newSocket readDataToData:[GCDAsyncSocket CRLFData] withTimeout:READ_TIMEOUT tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    // This method is executed on the socketQueue (not the main thread)
    
    if (tag == ECHO_MSG)
    {
        [sock readDataToData:[GCDAsyncSocket CRLFData] withTimeout:100 tag:0];
    }
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    
    NSLog(@"== didReadData %@ ==", sock.description);
    
    NSString *msg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    [self log:msg];
    [self perform:msg];
    [sock readDataWithTimeout:READ_TIMEOUT tag:0];
}

/**
 * This method is called if a read has timed out.
 * It allows us to optionally extend the timeout.
 * We use this method to issue a warning to the user prior to disconnecting them.
 **/
- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutReadWithTag:(long)tag
                 elapsed:(NSTimeInterval)elapsed
               bytesDone:(NSUInteger)length
{
    if (elapsed <= READ_TIMEOUT)
    {
        NSString *warningMsg = @"Are you still there?\r\n";
        NSData *warningData = [warningMsg dataUsingEncoding:NSUTF8StringEncoding];
        
        [sock writeData:warningData withTimeout:-1 tag:WARNING_MSG];
        
        return READ_TIMEOUT_EXTENSION;
    }
    return 0.0;
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
    if (sock != listenSocket)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                [self log:FORMAT(@"Client Disconnected")];
            }
        });
        
        @synchronized(connectedSockets)
        {
            [connectedSockets removeObject:sock];
        }
    }
}
- (void)perform:(NSString *)command {
    
    
    NSString *cmd = [command uppercaseString];
    
    NSLog(@"In Command");
    NSLog(@"%@",cmd);
    if ([cmd isEqualToString:@"UP"]) {
        NSLog(@"%f",speed);
        speed=speed+0.3;
        [self.Romo3 turnByAngle:0 withRadius:0.0 completion:^(BOOL success, float heading) {
            if (success) {
                [self.Romo3 driveForwardWithSpeed:speed];
            }
        }];
    }
    else if ([cmd isEqualToString:@"DOWN"]) {
        speed=speed-0.3;
        [self.Romo3 turnByAngle:0 withRadius:0.0 completion:^(BOOL success, float heading) {
            if (success) {
                [self.Romo3 driveForwardWithSpeed:speed];
            }
        }];
        
    }else if ([cmd isEqualToString:@"LEFT"]) {
        [self.Romo3 turnByAngle:-90 withRadius:0.0 completion:^(BOOL success, float heading) {
            if (success) {
                [self.Romo3 driveForwardWithSpeed:speed];
            }
        }];
    } else if ([cmd isEqualToString:@"RIGHT"]) {
        [self.Romo3 turnByAngle:90 withRadius:0.0 completion:^(BOOL success, float heading) {
            [self.Romo3 driveForwardWithSpeed:speed];
        }];
    } else if ([cmd isEqualToString:@"BACK"]) {
        [self.Romo3 driveBackwardWithSpeed:speed];
    } else if ([cmd isEqualToString:@"GO"]) {
        if(speed <= 0){
            speed = 0.3;
            [self.Romo3 driveForwardWithSpeed:speed];
            NSLog(@"%f",speed);
        }
        else{
            
            [self.Romo3 driveForwardWithSpeed:speed];NSLog(@"%f",speed);
        }
    } else if ([cmd isEqualToString:@"SMILE"]) {
        self.romoCharacter.expression=RMCharacterExpressionChuckle;
        self.romoCharacter.emotion=RMCharacterEmotionHappy;
    } else if([cmd isEqualToString:@"STOP"]){
        [self.Romo3 stopDriving];
    }
    else if ([cmd isEqualToString:@"FAST"]) {
        speed=speed+1.0;
        [self.Romo3 turnByAngle:0 withRadius:0.0 completion:^(BOOL success, float heading) {
            if (success) {
                [self.Romo3 driveForwardWithSpeed:speed];
            }
        }];
        NSLog(@"%f",speed);
    }
    else if ([cmd isEqualToString:@"SLOW"]) {
        if((speed-1.0) > 0){
            
            [self.Romo3 turnByAngle:0 withRadius:0.0 completion:^(BOOL success, float heading) {
                if (success) {
                    [self.Romo3 driveForwardWithSpeed:speed];
                }
            }];
        }
    }
    
    else if ([cmd isEqualToString:@"cam"]) {
        
    }
}

@end
