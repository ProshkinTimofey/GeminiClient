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

/*
 * ChatPlaceholderViewController — временный плейсхолдер до Шага 3 (ChatViewController).
 * Отображает статус сети и позволяет протестировать оба режима GeminiNetworkClient
 * прямо из UI ещё до написания полноценного чата.
 */
@interface ChatPlaceholderViewController : UIViewController <GeminiNetworkDelegate>
{
    GeminiNetworkClient *_client;
    UILabel             *_statusLabel;
    UILabel             *_modeLabel;
    UIButton            *_testButton;
    UIButton            *_modeButton;
    UITextView          *_responseView;
}
@property (nonatomic, retain) GeminiNetworkClient *client;
@property (nonatomic, retain) UILabel             *statusLabel;
@property (nonatomic, retain) UILabel             *modeLabel;
@property (nonatomic, retain) UIButton            *testButton;
@property (nonatomic, retain) UIButton            *modeButton;
@property (nonatomic, retain) UITextView          *responseView;
@end

@implementation ChatPlaceholderViewController

@synthesize client        = _client;
@synthesize statusLabel   = _statusLabel;
@synthesize modeLabel     = _modeLabel;
@synthesize testButton    = _testButton;
@synthesize modeButton    = _modeButton;
@synthesize responseView  = _responseView;

- (void)dealloc
{
    [_client release];
    [_statusLabel release];
    [_modeLabel release];
    [_testButton release];
    [_modeButton release];
    [_responseView release];
    [super dealloc];
}

- (void)loadView
{
    /* Корневой вид */
    UIView *root = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]];
    root.backgroundColor = [UIColor colorWithRed:0.07f green:0.07f blue:0.09f alpha:1.0f];
    self.view = root;
    [root release];

    CGFloat W = root.bounds.size.width;
    CGFloat Y = 20.0f;

    /* ── Лейбл режима ── */
    UILabel *modeL = [[UILabel alloc] initWithFrame:CGRectMake(16, Y, W - 32, 24)];
    modeL.textColor     = [UIColor colorWithRed:0.5f green:0.9f blue:0.5f alpha:1.0f];
    modeL.font          = [UIFont boldSystemFontOfSize:13.0f];
    modeL.textAlignment = UITextAlignmentCenter;
    modeL.backgroundColor = [UIColor clearColor];
    [root addSubview:modeL];
    self.modeLabel = modeL;
    [modeL release];
    Y += 32.0f;

    /* ── Кнопка переключения режима ── */
    UIButton *modeBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    modeBtn.frame = CGRectMake(16, Y, W - 32, 36);
    [modeBtn setTitle:@"Переключить режим" forState:UIControlStateNormal];
    [modeBtn addTarget:self action:@selector(toggleMode) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:modeBtn];
    self.modeButton = modeBtn;
    Y += 48.0f;

    /* ── Кнопка тест-запроса ── */
    UIButton *testBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    testBtn.frame = CGRectMake(16, Y, W - 32, 44);
    [testBtn setTitle:@"Отправить тест: «Привет!»" forState:UIControlStateNormal];
    [testBtn addTarget:self action:@selector(runTestRequest) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:testBtn];
    self.testButton = testBtn;
    Y += 56.0f;

    /* ── Лейбл статуса ── */
    UILabel *statusL = [[UILabel alloc] initWithFrame:CGRectMake(16, Y, W - 32, 20)];
    statusL.textColor     = [UIColor grayColor];
    statusL.font          = [UIFont systemFontOfSize:12.0f];
    statusL.textAlignment = UITextAlignmentCenter;
    statusL.backgroundColor = [UIColor clearColor];
    statusL.text          = @"Готово к отправке";
    [root addSubview:statusL];
    self.statusLabel = statusL;
    [statusL release];
    Y += 28.0f;

    /* ── TextView для ответа ── */
    UITextView *respView = [[UITextView alloc] initWithFrame:CGRectMake(8, Y, W - 16, root.bounds.size.height - Y - 8)];
    respView.editable         = NO;
    respView.textColor        = [UIColor whiteColor];
    respView.backgroundColor  = [UIColor colorWithRed:0.12f green:0.12f blue:0.15f alpha:1.0f];
    respView.font             = [UIFont systemFontOfSize:13.0f];
    respView.text             = @"(ответ появится здесь)";
    [root addSubview:respView];
    self.responseView = respView;
    [respView release];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Gemini Client";
    [self updateModeLabel];
}

- (void)updateModeLabel
{
    GeminiNetworkMode mode = [self.client currentMode];
    if (mode == GeminiNetworkModeProxy) {
        self.modeLabel.text = @"Режим A: Proxy / REST API (iOS 3.0 safe)";
    } else {
        self.modeLabel.text = @"Режим B: Прямой batchexecute + куки";
    }
}

- (void)toggleMode
{
    GeminiNetworkMode mode = [self.client currentMode];
    if (mode == GeminiNetworkModeProxy) {
        [self.client setMode:GeminiNetworkModeDirectRPC];
    } else {
        [self.client setMode:GeminiNetworkModeProxy];
    }
    [self updateModeLabel];
}

- (void)runTestRequest
{
    self.statusLabel.text    = @"Отправка…";
    self.responseView.text   = @"";
    [self.client sendPrompt:@"Привет! Расскажи в одном предложении, что такое Gemini." delegate:self];
}

/* ── GeminiNetworkDelegate ── */

- (void)networkClient:(GeminiNetworkClient *)client didReceiveReply:(NSString *)reply
{
    /* Уже на главном потоке — делегат гарантирует это */
    self.statusLabel.text  = @"Готово ✓";
    self.responseView.text = reply;
}

- (void)networkClient:(GeminiNetworkClient *)client didFailWithError:(NSError *)error
{
    self.statusLabel.text  = @"Ошибка";
    self.responseView.text = [error localizedDescription];
}

@end

/* ════════════════════════════════════════════════════════════════════════════ */
/*                               AppDelegate                                   */
/* ════════════════════════════════════════════════════════════════════════════ */

@implementation AppDelegate

@synthesize window        = _window;
@synthesize navController = _navController;
@synthesize networkClient = _networkClient;

- (void)dealloc
{
    [_window release];
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

    /* ── Корневой контроллер ── */
    ChatPlaceholderViewController *root = [[ChatPlaceholderViewController alloc] init];
    root.client = self.networkClient;

    UINavigationController *nav = [[UINavigationController alloc]
                                    initWithRootViewController:root];
    [root release];
    self.navController = nav;
    [nav release];

    self.window.rootViewController = self.navController;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    /* iOS 3.0 совместимость: нет applicationDidReceiveMemoryWarning: в UIApplicationDelegate
     * как протокольный метод — но работает как обычный UIApplicationDelegate callback */
    NSLog(@"[GeminiClient] Memory warning received");
}

@end
