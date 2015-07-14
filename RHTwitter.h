

#import <Foundation/Foundation.h>

@interface RHTwitter : NSObject

- (void)fetchTweetsWithCompletionBlock:(void (^)(NSArray *tweets))completionBlock;

@end
