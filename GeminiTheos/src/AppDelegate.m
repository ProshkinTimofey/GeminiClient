/*
 * AppDelegate.m — GeminiClient (Theos, MRC, iOS 3.0+)
 *
 * iOS 3.0 совместимость:
 *   - UIWindow frame задаётся через [UIScreen mainScreen].bounds.
 *   - Нет storyboard / XIB — всё создаётся программно.
 *   - UINavigationController инициализируется с rootViewController.
 *   - [window makeKeyAndVisible] — стандарт с iOS 2.0.
 */

#import "AppDelegate.h"
#import "GeminiNetworkClient.h"
#import "ChatViewController.h"

@implementation AppDelegate

@synthesize window        = _window;
@synthesize navController = _navController;
@synthesize networkClient = _networkClient;

- (void)dealloc
{
    [_window      release];
    [_navController release];
    [_networkClient release];
    [super dealloc];
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    /* ── Создаём окно ── */
    UIWindow *win = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window = win;
    [win release];

    /* ── Сетевой клиент ── */
    GeminiNetworkClient *net = [[GeminiNetworkClient alloc] init];
    self.networkClient = net;
    [net release];

    /* ── Корневой контроллер — чат ── */
    ChatViewController *chat = [[ChatViewController alloc]
                                 initWithNetworkClient:self.networkClient];

    UINavigationController *nav = [[UINavigationController alloc]
                                    initWithRootViewController:chat];
    [chat release];

    /* Стиль навбара */
    nav.navigationBar.barStyle   = UIBarStyleBlack;
    nav.navigationBar.translucent = NO;

    self.navController = nav;
    [nav release];

    self.window.rootViewController = self.navController;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    NSLog(@"[GeminiClient] Memory warning");
}

@end
