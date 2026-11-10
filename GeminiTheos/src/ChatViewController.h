/*
 * ChatViewController.h — GeminiClient (Theos, MRC, iOS 3.0+)
 *
 * Классический экран чата:
 *   - UITableView (на весь экран)
 *   - Панель ввода: UITextField + UIButton «Отправить»
 *   - Делегат GeminiNetworkDelegate: пишет ответы в массив + reloadData
 *   - Кнопка Settings в NavBar → modally показывает SettingsViewController
 *
 * iOS 3.0 совместимость:
 *   - MRC, никаких блоков, никакого AutoLayout
 *   - Клавиатура обрабатывается через UIKeyboardWillShowNotification /
 *     UIKeyboardWillHideNotification + ручной сдвиг фреймов
 *   - scrollToRowAtIndexPath:atScrollPosition:animated: (iOS 2.0+)
 */

#import <UIKit/UIKit.h>
#import "GeminiNetworkClient.h"
#import "ChatMessageCell.h"

@interface ChatViewController : UIViewController
    <UITableViewDataSource,
     UITableViewDelegate,
     UITextFieldDelegate,
     GeminiNetworkDelegate>
{
    /* ── Данные ── */
    NSMutableArray      *_messages;          /* массив ChatMessage* */
    GeminiNetworkClient *_networkClient;     /* assign — владеет AppDelegate */

    /* ── UI ── */
    UITableView         *_tableView;

    /* Панель ввода */
    UIView              *_inputBar;
    UITextField         *_inputField;
    UIButton            *_sendButton;

    /* Индикатор «печатает…» */
    UIActivityIndicatorView *_activityIndicator;
    UILabel                 *_typingLabel;

    /* Флаг ожидания ответа */
    BOOL                 _isWaiting;

    /* Запомненная высота клавиатуры для ручного layout */
    CGFloat              _keyboardHeight;
}

/* assign — не владеем клиентом */
@property (nonatomic, assign) GeminiNetworkClient *networkClient;

/* retain — владеем данными и UI */
@property (nonatomic, retain) NSMutableArray      *messages;
@property (nonatomic, retain) UITableView         *tableView;
@property (nonatomic, retain) UIView              *inputBar;
@property (nonatomic, retain) UITextField         *inputField;
@property (nonatomic, retain) UIButton            *sendButton;
@property (nonatomic, retain) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, retain) UILabel             *typingLabel;

- (id)initWithNetworkClient:(GeminiNetworkClient *)client;

@end
