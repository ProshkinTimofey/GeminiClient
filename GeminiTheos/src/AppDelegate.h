/*
 * AppDelegate.h — GeminiClient (Theos, MRC, iOS 3.0+)
 */

#import <UIKit/UIKit.h>

@class GeminiNetworkClient;

@interface AppDelegate : NSObject <UIApplicationDelegate>
{
    UIWindow              *_window;
    UINavigationController *_navController;
    GeminiNetworkClient   *_networkClient;
}

@property (nonatomic, retain) UIWindow              *window;
@property (nonatomic, retain) UINavigationController *navController;
@property (nonatomic, retain) GeminiNetworkClient   *networkClient;

@end
