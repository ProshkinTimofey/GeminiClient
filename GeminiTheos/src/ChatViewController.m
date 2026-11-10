/*
 * ChatViewController.m — GeminiClient (Theos, MRC, iOS 3.0+)
 *
 * iOS 3.0 совместимость:
 *   - MRC: retain/release/dealloc, никакого ARC.
 *   - Никакого AutoLayout — все фреймы через CGRect.
 *   - Клавиатура: UIKeyboardWillShowNotification / UIKeyboardWillHideNotification.
 *   - scrollToRowAtIndexPath:atScrollPosition:animated: — iOS 2.0+.
 *   - sizeWithFont:constrainedToSize:lineBreakMode: — iOS 2.0+.
 *   - UILineBreakModeWordWrap вместо NSLineBreakByWordWrapping.
 *   - Никакого UIKeyboardFrameEndUserInfoKey (доступен с iOS 3.2) —
 *     используем UIKeyboardBoundsUserInfoKey (iOS 2.0) как фоллбэк.
 */

#import "ChatViewController.h"
#import "ChatMessageCell.h"
#import "SettingsViewController.h"
#import "GeminiNetworkClient.h"

/* Высота нижней панели ввода */
static const CGFloat kInputBarH         = 48.0f;
static const CGFloat kInputFieldPad     = 8.0f;
static const CGFloat kSendBtnW          = 72.0f;
static const CGFloat kTypingLabelH      = 20.0f;

static NSString * const kCellReuseID   = @"ChatCell";

/* ════════════════════════════════════════════════════════════════════════════
 * ChatViewController
 * ════════════════════════════════════════════════════════════════════════════ */

@implementation ChatViewController

@synthesize networkClient    = _networkClient;
@synthesize messages         = _messages;
@synthesize tableView        = _tableView;
@synthesize inputBar         = _inputBar;
@synthesize inputField       = _inputField;
@synthesize sendButton       = _sendButton;
@synthesize activityIndicator = _activityIndicator;
@synthesize typingLabel      = _typingLabel;

/* ── Инициализация ── */
- (id)initWithNetworkClient:(GeminiNetworkClient *)client
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _networkClient  = client; /* assign — владеет AppDelegate */
        _messages       = [[NSMutableArray alloc] init];
        _keyboardHeight = 0.0f;
        _isWaiting      = NO;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_messages          release];
    [_tableView         release];
    [_inputBar          release];
    [_inputField        release];
    [_sendButton        release];
    [_activityIndicator release];
    [_typingLabel       release];
    [super dealloc];
}

/* ════════════════════════════════════════════════════════════════════════════
 * Построение UI (всё вручную, без XIB/Storyboard)
 * ════════════════════════════════════════════════════════════════════════════ */

- (void)loadView
{
    UIView *root = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]];
    root.backgroundColor = [UIColor colorWithRed:0.07f green:0.07f blue:0.09f alpha:1.0f];
    self.view = root;
    [root release];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Gemini";

    /* ── Кнопка Settings в правом углу NavBar ── */
    UIBarButtonItem *settingsBtn = [[UIBarButtonItem alloc]
        initWithTitle:@"⚙"
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(_openSettings)];
    self.navigationItem.rightBarButtonItem = settingsBtn;
    [settingsBtn release];

    /* ── Начальное приветствие в массиве ── */
    ChatMessage *welcome = [ChatMessage messageWithText:@"Привет! Я Gemini. Задай любой вопрос."
                                                 isUser:NO];
    [self.messages addObject:welcome];

    [self _buildTableView];
    [self _buildInputBar];
    [self _buildTypingIndicator];
    [self _applyLayout];

    /* ── Подписка на клавиатуру ── */
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_keyboardWillShow:)
               name:UIKeyboardWillShowNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_keyboardWillHide:)
               name:UIKeyboardWillHideNotification
             object:nil];
}

- (void)_buildTableView
{
    UITableView *tv = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tv.dataSource       = self;
    tv.delegate         = self;
    tv.backgroundColor  = [UIColor colorWithRed:0.07f green:0.07f blue:0.09f alpha:1.0f];
    tv.separatorStyle   = UITableViewCellSeparatorStyleNone;
    tv.showsVerticalScrollIndicator = YES;
    /* iOS 3.0: нет tv.contentInset из-за клавиатуры — управляем вручную */
    [self.view addSubview:tv];
    self.tableView = tv;
    [tv release];
}

- (void)_buildInputBar
{
    UIView *bar = [[UIView alloc] initWithFrame:CGRectZero];
    bar.backgroundColor = [UIColor colorWithRed:0.11f green:0.11f blue:0.14f alpha:1.0f];

    /* Верхняя разделительная линия */
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 1)];
    line.backgroundColor = [UIColor colorWithRed:0.25f green:0.25f blue:0.3f alpha:1.0f];
    [bar addSubview:line];
    [line release];

    /* Текстовое поле */
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
    field.placeholder            = @"Введите сообщение…";
    field.font                   = [UIFont systemFontOfSize:14.0f];
    field.textColor              = [UIColor whiteColor];
    field.backgroundColor        = [UIColor colorWithRed:0.17f green:0.17f blue:0.21f alpha:1.0f];
    field.layer.cornerRadius     = 16.0f;
    field.returnKeyType          = UIReturnKeySend;
    field.delegate               = self;
    field.autocorrectionType     = UITextAutocorrectionTypeDefault;
    field.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    /* Левый отступ */
    UIView *leftPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, kInputBarH)];
    field.leftView     = leftPad;
    field.leftViewMode = UITextFieldViewModeAlways;
    [leftPad release];
    [bar addSubview:field];
    self.inputField = field;
    [field release];

    /* Кнопка «Отправить» */
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    [btn setTitle:@"▶" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor colorWithRed:0.14f green:0.49f blue:0.96f alpha:1.0f]
              forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor grayColor] forState:UIControlStateDisabled];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:20.0f];
    [btn addTarget:self
            action:@selector(_sendTapped)
  forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:btn];
    self.sendButton = btn;

    [self.view addSubview:bar];
    self.inputBar = bar;
    [bar release];
}

- (void)_buildTypingIndicator
{
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    spinner.hidden = YES;
    [self.view addSubview:spinner];
    self.activityIndicator = spinner;
    [spinner release];

    UILabel *typingL = [[UILabel alloc] initWithFrame:CGRectZero];
    typingL.text            = @"Gemini печатает…";
    typingL.font            = [UIFont italicSystemFontOfSize:12.0f];
    typingL.textColor       = [UIColor grayColor];
    typingL.backgroundColor = [UIColor clearColor];
    typingL.hidden          = YES;
    [self.view addSubview:typingL];
    self.typingLabel = typingL;
    [typingL release];
}

/* ════════════════════════════════════════════════════════════════════════════
 * Layout (вызывается при изменении размера или клавиатуры)
 * ════════════════════════════════════════════════════════════════════════════ */

- (void)_applyLayout
{
    CGRect bounds = self.view.bounds;
    CGFloat W = bounds.size.width;
    CGFloat H = bounds.size.height;

    /* Высота вида за вычетом клавиатуры */
    CGFloat availH = H - _keyboardHeight;

    /* ── Панель ввода — прижата к низу ── */
    CGFloat barY = availH - kInputBarH;
    self.inputBar.frame = CGRectMake(0, barY, W, kInputBarH);

    /* Линия-разделитель (первый subview) */
    UIView *line = [[self.inputBar subviews] objectAtIndex:0];
    line.frame = CGRectMake(0, 0, W, 1);

    /* Поле ввода */
    CGFloat fieldW = W - kInputFieldPad * 2.0f - kSendBtnW - 4.0f;
    self.inputField.frame = CGRectMake(kInputFieldPad,
                                        (kInputBarH - 34.0f) / 2.0f,
                                        fieldW,
                                        34.0f);

    /* Кнопка «Отправить» */
    self.sendButton.frame = CGRectMake(W - kSendBtnW - kInputFieldPad,
                                        (kInputBarH - 36.0f) / 2.0f,
                                        kSendBtnW,
                                        36.0f);

    /* ── Индикатор «печатает» — над панелью ввода ── */
    if (!self.typingLabel.hidden) {
        CGFloat indicatorY = barY - kTypingLabelH - 2.0f;
        self.activityIndicator.frame = CGRectMake(kInputFieldPad,
                                                   indicatorY + 2.0f,
                                                   16.0f, 16.0f);
        self.typingLabel.frame = CGRectMake(kInputFieldPad + 20.0f,
                                             indicatorY,
                                             200.0f,
                                             kTypingLabelH);
    }

    /* ── TableView — сверху до панели (или до индикатора) ── */
    CGFloat tableH = barY;
    if (!self.typingLabel.hidden) {
        tableH -= (kTypingLabelH + 4.0f);
    }
    self.tableView.frame = CGRectMake(0, 0, W, tableH);
}

- (void)viewWillLayoutSubviews
{
    [self _applyLayout];
}

/* ════════════════════════════════════════════════════════════════════════════
 * Клавиатура
 * ════════════════════════════════════════════════════════════════════════════ */

- (void)_keyboardWillShow:(NSNotification *)note
{
    NSDictionary *info = [note userInfo];

    /* iOS 3.2+: UIKeyboardFrameEndUserInfoKey
     * iOS 2.0–3.1: UIKeyboardBoundsUserInfoKey — высота в .size.height */
    CGFloat kbH = 0.0f;

    NSValue *endFrameVal = [info objectForKey:UIKeyboardFrameEndUserInfoKey];
    if (endFrameVal) {
        CGRect kbRect = [endFrameVal CGRectValue];
        /* Конвертируем из экранных координат — ключ даёт frame в window space */
        CGRect kbInView = [self.view convertRect:kbRect fromView:nil];
        kbH = self.view.bounds.size.height - kbInView.origin.y;
        if (kbH < 0) { kbH = 0; }
    } else {
        /* Фоллбэк для iOS 2.0–3.1 */
        NSValue *boundsVal = [info objectForKey:@"UIKeyboardBoundsUserInfoKey"];
        if (boundsVal) {
            CGRect kbBounds = [boundsVal CGRectValue];
            kbH = kbBounds.size.height;
        }
    }

    _keyboardHeight = kbH;

    NSNumber *durationNum = [info objectForKey:UIKeyboardAnimationDurationUserInfoKey];
    NSTimeInterval dur = durationNum ? [durationNum doubleValue] : 0.25;

    [UIView beginAnimations:@"kbShow" context:NULL];
    [UIView setAnimationDuration:dur];
    [self _applyLayout];
    [UIView commitAnimations];

    [self _scrollToBottom:NO];
}

- (void)_keyboardWillHide:(NSNotification *)note
{
    _keyboardHeight = 0.0f;

    NSDictionary *info = [note userInfo];
    NSNumber *durationNum = [info objectForKey:UIKeyboardAnimationDurationUserInfoKey];
    NSTimeInterval dur = durationNum ? [durationNum doubleValue] : 0.25;

    [UIView beginAnimations:@"kbHide" context:NULL];
    [UIView setAnimationDuration:dur];
    [self _applyLayout];
    [UIView commitAnimations];
}

/* ════════════════════════════════════════════════════════════════════════════
 * UITableViewDataSource
 * ════════════════════════════════════════════════════════════════════════════ */

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)[self.messages count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    ChatMessageCell *cell = (ChatMessageCell *)[tableView
        dequeueReusableCellWithIdentifier:kCellReuseID];
    if (!cell) {
        cell = [[[ChatMessageCell alloc]
                  initWithStyle:UITableViewCellStyleDefault
                reuseIdentifier:kCellReuseID] autorelease];
    }

    ChatMessage *msg = [self.messages objectAtIndex:(NSUInteger)indexPath.row];
    [cell setMessage:msg];
    return cell;
}

/* ════════════════════════════════════════════════════════════════════════════
 * UITableViewDelegate — высота ячеек
 * ════════════════════════════════════════════════════════════════════════════ */

- (CGFloat)tableView:(UITableView *)tableView
heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    ChatMessage *msg = [self.messages objectAtIndex:(NSUInteger)indexPath.row];
    return [ChatMessageCell cellHeightForMessage:msg
                                     tableWidth:tableView.bounds.size.width];
}

/* Запрет выделения */
- (NSIndexPath *)tableView:(UITableView *)tableView
  willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}

/* ════════════════════════════════════════════════════════════════════════════
 * UITextFieldDelegate
 * ════════════════════════════════════════════════════════════════════════════ */

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self _sendTapped];
    return NO;
}

/* ════════════════════════════════════════════════════════════════════════════
 * Отправка сообщения
 * ════════════════════════════════════════════════════════════════════════════ */

- (void)_sendTapped
{
    NSString *text = [self.inputField.text
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text length] == 0 || _isWaiting) { return; }

    /* 1. Добавляем сообщение пользователя в таблицу */
    ChatMessage *userMsg = [ChatMessage messageWithText:text isUser:YES];
    [self.messages addObject:userMsg];
    [self.tableView reloadData];
    [self _scrollToBottom:YES];

    /* 2. Очищаем поле */
    self.inputField.text = @"";

    /* 3. Показываем «Gemini печатает…» */
    [self _setWaiting:YES];

    /* 4. Отправляем через сетевой клиент */
    [self.networkClient sendPrompt:text delegate:self];
}

- (void)_setWaiting:(BOOL)waiting
{
    _isWaiting = waiting;
    self.sendButton.enabled     = !waiting;
    self.inputField.enabled     = !waiting;
    self.typingLabel.hidden     = !waiting;
    self.activityIndicator.hidden = !waiting;

    if (waiting) {
        [self.activityIndicator startAnimating];
    } else {
        [self.activityIndicator stopAnimating];
    }

    [self _applyLayout];
}

/* ════════════════════════════════════════════════════════════════════════════
 * GeminiNetworkDelegate — вызывается на главном потоке
 * ════════════════════════════════════════════════════════════════════════════ */

- (void)networkClient:(GeminiNetworkClient *)client
     didReceiveReply:(NSString *)reply
{
    /* Скрываем индикатор */
    [self _setWaiting:NO];

    /* Добавляем ответ в таблицу */
    ChatMessage *botMsg = [ChatMessage messageWithText:reply isUser:NO];
    [self.messages addObject:botMsg];
    [self.tableView reloadData];
    [self _scrollToBottom:YES];
}

- (void)networkClient:(GeminiNetworkClient *)client
     didFailWithError:(NSError *)error
{
    [self _setWaiting:NO];

    /* Показываем ошибку как системное сообщение */
    NSString *errText = [NSString stringWithFormat:@"⚠ Ошибка: %@",
                         [error localizedDescription]];
    ChatMessage *errMsg = [ChatMessage messageWithText:errText isUser:NO];
    [self.messages addObject:errMsg];
    [self.tableView reloadData];
    [self _scrollToBottom:YES];
}

/* ════════════════════════════════════════════════════════════════════════════
 * Вспомогательные методы
 * ════════════════════════════════════════════════════════════════════════════ */

- (void)_scrollToBottom:(BOOL)animated
{
    NSUInteger count = [self.messages count];
    if (count == 0) { return; }

    NSIndexPath *last = [NSIndexPath indexPathForRow:(NSInteger)(count - 1)
                                           inSection:0];
    [self.tableView scrollToRowAtIndexPath:last
                          atScrollPosition:UITableViewScrollPositionBottom
                                  animated:animated];
}

- (void)_openSettings
{
    SettingsViewController *sv = [[SettingsViewController alloc]
                                   initWithNetworkClient:self.networkClient];
    sv.delegate = (id<SettingsViewControllerDelegate>)self;
    [self.navigationController pushViewController:sv animated:YES];
    [sv release];
}

/* ── Принимаем callback от Settings (опционально) ── */
- (void)settingsViewControllerDidSave:(SettingsViewController *)vc
{
    /* После сохранения настроек — обновляем заголовок с текущим режимом */
    GeminiNetworkMode mode = [self.networkClient currentMode];
    if (mode == GeminiNetworkModeProxy) {
        self.title = @"Gemini (Шлюз)";
    } else {
        self.title = @"Gemini (RPC)";
    }
}

/* ── Скрываем клавиатуру по тапу на таблицу ── */
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [self.inputField resignFirstResponder];
}

@end
