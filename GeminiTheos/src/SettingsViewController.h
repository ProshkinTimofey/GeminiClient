/*
 * SettingsViewController.h — GeminiClient (Theos, MRC, iOS 3.0+)
 *
 * Экран настроек сетевого движка. Сохраняет параметры в NSUserDefaults.
 * Всё через retain/release, никаких блоков, никаких UIStackView.
 */

#import <UIKit/UIKit.h>
#import "GeminiNetworkClient.h"

@class SettingsViewController;

@protocol SettingsViewControllerDelegate <NSObject>
@optional
/* Вызывается после успешного сохранения настроек */
- (void)settingsViewControllerDidSave:(SettingsViewController *)vc;
@end

/* ══════════════════════════════════════════════════════════════════════════ */

@interface SettingsViewController : UIViewController <UITextFieldDelegate>
{
    /* ── Режим ── */
    UILabel             *_modeLabel;
    UISegmentedControl  *_modeSegment;

    /* ── Секция: Шлюз / API ── */
    UILabel             *_proxyLabel;
    UITextField         *_proxyField;        /* ProxyURL или googleapis endpoint */
    UILabel             *_apiKeyLabel;
    UITextField         *_apiKeyField;       /* Gemini API Key */

    /* ── Секция: Direct RPC ── */
    UILabel             *_cookieLabel;
    UITextField         *_cookieField;       /* __Secure-1PSID */
    UILabel             *_snlmLabel;
    UITextField         *_snlmField;         /* SNlM0e токен */

    /* ── Модель ── */
    UILabel             *_modelLabel;
    UITextField         *_modelField;        /* gemini-2.0-flash и т.д. */

    /* ── Кнопки ── */
    UIButton            *_saveButton;
    UIButton            *_cancelButton;

    /* ── Scroll ── */
    UIScrollView        *_scrollView;

    /* Слабая ссылка (assign) на сетевой клиент — владеет AppDelegate */
    GeminiNetworkClient *_networkClient;

    /* Слабая ссылка на делегат */
    id<SettingsViewControllerDelegate> _delegate;
}

@property (nonatomic, retain)  UIScrollView           *scrollView;
@property (nonatomic, retain)  UISegmentedControl     *modeSegment;
@property (nonatomic, retain)  UITextField            *proxyField;
@property (nonatomic, retain)  UITextField            *apiKeyField;
@property (nonatomic, retain)  UITextField            *cookieField;
@property (nonatomic, retain)  UITextField            *snlmField;
@property (nonatomic, retain)  UITextField            *modelField;
@property (nonatomic, retain)  UIButton               *saveButton;
@property (nonatomic, retain)  UIButton               *cancelButton;

/* assign — не владеем */
@property (nonatomic, assign)  GeminiNetworkClient                *networkClient;
@property (nonatomic, assign)  id<SettingsViewControllerDelegate>  delegate;

- (id)initWithNetworkClient:(GeminiNetworkClient *)client;

@end
