/*
 * SettingsViewController.m — GeminiClient (Theos, MRC, iOS 3.0+)
 *
 * iOS 3.0 совместимость:
 *   - MRC: retain/release/dealloc, никакого ARC.
 *   - Никаких UIStackView, AutoLayout, констрейнтов.
 *   - Layout — ручной в viewWillLayoutSubviews.
 *   - UISegmentedControl и UITextField — iOS 2.0+.
 *   - UIScrollView для прокрутки формы при маленьком экране.
 *   - Клавиатура: UIKeyboardWillShowNotification / UIKeyboardWillHideNotification.
 */

#import "SettingsViewController.h"

/* Константы геометрии */
static const CGFloat kFormPadH   = 16.0f;
static const CGFloat kFormPadV   = 12.0f;
static const CGFloat kLabelH     = 20.0f;
static const CGFloat kFieldH     = 36.0f;
static const CGFloat kSegmentH   = 32.0f;
static const CGFloat kBtnH       = 44.0f;
static const CGFloat kSpacing    = 8.0f;

/* ════════════════════════════════════════════════════════════════════════════
 * Вспомогательные строители UI (не блоки — статические C-функции)
 * ════════════════════════════════════════════════════════════════════════════ */

static UILabel *make_label(NSString *text, CGFloat fontSize, BOOL bold)
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text          = text;
    l.font          = bold ? [UIFont boldSystemFontOfSize:fontSize]
                           : [UIFont systemFontOfSize:fontSize];
    l.textColor     = [UIColor colorWithRed:0.75f green:0.75f blue:0.78f alpha:1.0f];
    l.backgroundColor = [UIColor clearColor];
    return [l autorelease]; /* caller добавляет в subview до исчезновения пула */
}

static UITextField *make_field(NSString *placeholder, BOOL secure)
{
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectZero];
    f.placeholder          = placeholder;
    f.secureTextEntry      = secure;
    f.font                 = [UIFont systemFontOfSize:13.0f];
    f.textColor            = [UIColor whiteColor];
    f.backgroundColor      = [UIColor colorWithRed:0.14f green:0.14f blue:0.17f alpha:1.0f];
    f.layer.cornerRadius   = 7.0f;
    f.clearButtonMode      = UITextFieldViewModeWhileEditing;
    f.autocorrectionType   = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.returnKeyType        = UIReturnKeyDone;
    /* Внутренний отступ — не UIEdgeInsets в iOS3, делаем через leftView */
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, kFieldH)];
    f.leftView     = pad;
    f.leftViewMode = UITextFieldViewModeAlways;
    [pad release];
    return [f autorelease];
}

/* ════════════════════════════════════════════════════════════════════════════
 * SettingsViewController
 * ════════════════════════════════════════════════════════════════════════════ */

@implementation SettingsViewController

@synthesize scrollView    = _scrollView;
@synthesize modeSegment   = _modeSegment;
@synthesize proxyField    = _proxyField;
@synthesize apiKeyField   = _apiKeyField;
@synthesize cookieField   = _cookieField;
@synthesize snlmField     = _snlmField;
@synthesize modelField    = _modelField;
@synthesize saveButton    = _saveButton;
@synthesize cancelButton  = _cancelButton;
@synthesize networkClient = _networkClient;
@synthesize delegate      = _delegate;

- (id)initWithNetworkClient:(GeminiNetworkClient *)client
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _networkClient = client; /* assign — не retain */
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_scrollView   release];
    [_modeLabel    release];
    [_modeSegment  release];
    [_proxyLabel   release];
    [_proxyField   release];
    [_apiKeyLabel  release];
    [_apiKeyField  release];
    [_cookieLabel  release];
    [_cookieField  release];
    [_snlmLabel    release];
    [_snlmField    release];
    [_modelLabel   release];
    [_modelField   release];
    [_saveButton   release];
    [_cancelButton release];
    [super dealloc];
}

/* ── Построение UI ── */
- (void)loadView
{
    UIView *root = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]];
    root.backgroundColor = [UIColor colorWithRed:0.07f green:0.07f blue:0.09f alpha:1.0f];
    self.view = root;
    [root release];

    /* ── ScrollView ── */
    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:root.bounds];
    sv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sv.backgroundColor  = [UIColor clearColor];
    sv.alwaysBounceVertical = YES;
    [root addSubview:sv];
    self.scrollView = sv;
    [sv release];

    /* ── Строим секции внутри scrollView ── */
    CGFloat W = root.bounds.size.width;
    CGFloat Y = kFormPadV;
    CGFloat fw = W - kFormPadH * 2.0f;  /* ширина поля */

    /* ─── Секция: Режим ─────────────────── */
    UILabel *modeL = make_label(@"РЕЖИМ РАБОТЫ", 11.0f, NO);
    modeL.frame = CGRectMake(kFormPadH, Y, fw, kLabelH);
    [sv addSubview:modeL];
    _modeLabel = [modeL retain];
    Y += kLabelH + 4.0f;

    NSArray *modes = [NSArray arrayWithObjects:@"A: Шлюз / API", @"B: Direct RPC", nil];
    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:modes];
    seg.frame = CGRectMake(kFormPadH, Y, fw, kSegmentH);
    seg.selectedSegmentIndex = 0;
    [seg addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [sv addSubview:seg];
    self.modeSegment = seg;
    [seg release];
    Y += kSegmentH + kFormPadV;

    /* ─── Секция A: Шлюз ──────────────── */
    UILabel *proxyL = make_label(@"URL шлюза или googleapis endpoint", 11.0f, NO);
    proxyL.frame = CGRectMake(kFormPadH, Y, fw, kLabelH);
    [sv addSubview:proxyL];
    _proxyLabel = [proxyL retain];
    Y += kLabelH + 4.0f;

    UITextField *proxyF = make_field(@"http://your-proxy.example.com/api/chat", NO);
    proxyF.frame = CGRectMake(kFormPadH, Y, fw, kFieldH);
    proxyF.delegate = self;
    proxyF.keyboardType = UIKeyboardTypeURL;
    [sv addSubview:proxyF];
    self.proxyField = proxyF;
    Y += kFieldH + kSpacing;

    UILabel *apiL = make_label(@"Google AI Studio API Key (для googleapis)", 11.0f, NO);
    apiL.frame = CGRectMake(kFormPadH, Y, fw, kLabelH);
    [sv addSubview:apiL];
    _apiKeyLabel = [apiL retain];
    Y += kLabelH + 4.0f;

    UITextField *apiF = make_field(@"AIzaSy...", NO);
    apiF.frame = CGRectMake(kFormPadH, Y, fw, kFieldH);
    apiF.delegate = self;
    [sv addSubview:apiF];
    self.apiKeyField = apiF;
    Y += kFieldH + kFormPadV;

    /* ─── Секция B: Direct RPC ─────────── */
    UILabel *cookieL = make_label(@"__Secure-1PSID (Cookie сессии Gemini)", 11.0f, NO);
    cookieL.frame = CGRectMake(kFormPadH, Y, fw, kLabelH);
    [sv addSubview:cookieL];
    _cookieLabel = [cookieL retain];
    Y += kLabelH + 4.0f;

    UITextField *cookieF = make_field(@"g.a0AX...", YES);
    cookieF.frame = CGRectMake(kFormPadH, Y, fw, kFieldH);
    cookieF.delegate = self;
    [sv addSubview:cookieF];
    self.cookieField = cookieF;
    Y += kFieldH + kSpacing;

    UILabel *snlmL = make_label(@"SNlM0e токен (CSRF, из DevTools)", 11.0f, NO);
    snlmL.frame = CGRectMake(kFormPadH, Y, fw, kLabelH);
    [sv addSubview:snlmL];
    _snlmLabel = [snlmL retain];
    Y += kLabelH + 4.0f;

    UITextField *snlmF = make_field(@"SNlM0e=...", NO);
    snlmF.frame = CGRectMake(kFormPadH, Y, fw, kFieldH);
    snlmF.delegate = self;
    [sv addSubview:snlmF];
    self.snlmField = snlmF;
    Y += kFieldH + kFormPadV;

    /* ─── Общая секция: Модель ─────────── */
    UILabel *modelL = make_label(@"Модель (gemini-2.0-flash / gemini-1.5-pro)", 11.0f, NO);
    modelL.frame = CGRectMake(kFormPadH, Y, fw, kLabelH);
    [sv addSubview:modelL];
    _modelLabel = [modelL retain];
    Y += kLabelH + 4.0f;

    UITextField *modelF = make_field(@"gemini-2.0-flash", NO);
    modelF.frame = CGRectMake(kFormPadH, Y, fw, kFieldH);
    modelF.delegate = self;
    [sv addSubview:modelF];
    self.modelField = modelF;
    Y += kFieldH + kFormPadV * 2.0f;

    /* ─── Кнопка «Сохранить» ─────────── */
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    saveBtn.frame = CGRectMake(kFormPadH, Y, fw, kBtnH);
    [saveBtn setTitle:@"Сохранить" forState:UIControlStateNormal];
    saveBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16.0f];
    [saveBtn addTarget:self action:@selector(saveSettings) forControlEvents:UIControlEventTouchUpInside];
    [sv addSubview:saveBtn];
    self.saveButton = saveBtn;
    Y += kBtnH + kSpacing;

    /* ─── Кнопка «Отмена» ─────────────── */
    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    cancelBtn.frame = CGRectMake(kFormPadH, Y, fw, kBtnH);
    [cancelBtn setTitle:@"Отмена" forState:UIControlStateNormal];
    [cancelBtn setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
    [cancelBtn addTarget:self action:@selector(cancelSettings) forControlEvents:UIControlEventTouchUpInside];
    [sv addSubview:cancelBtn];
    self.cancelButton = cancelBtn;
    Y += kBtnH + kFormPadV;

    sv.contentSize = CGSizeMake(W, Y);
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Настройки";

    /* Загрузить текущие настройки в поля */
    [self _loadCurrentSettings];

    /* Подписка на клавиатуру */
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

- (void)_loadCurrentSettings
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    NSInteger mode = [d integerForKey:kGeminiPrefMode];
    self.modeSegment.selectedSegmentIndex = (mode == GeminiNetworkModeDirectRPC) ? 1 : 0;

    NSString *proxy = [d stringForKey:kGeminiPrefProxyURL];
    if (proxy) { self.proxyField.text = proxy; }

    NSString *api = [d stringForKey:kGeminiPrefAPIKey];
    if (api) { self.apiKeyField.text = api; }

    NSString *cookie = [d stringForKey:kGeminiPrefSessionCookie];
    if (cookie) { self.cookieField.text = cookie; }

    NSString *snlm = [d stringForKey:kGeminiPrefSNlM0e];
    if (snlm) { self.snlmField.text = snlm; }

    NSString *model = [d stringForKey:kGeminiPrefModel];
    if (model && [model length] > 0) { self.modelField.text = model; }
    else { self.modelField.text = @"gemini-2.0-flash"; }
}

/* ── Смена режима ── */
- (void)modeChanged:(UISegmentedControl *)seg
{
    /* Нет визуальных скрытий — всегда оба блока видны (экран достаточно прокручивается) */
}

/* ── Сохранить ── */
- (void)saveSettings
{
    [self.view endEditing:YES];

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    NSInteger modeIdx = self.modeSegment.selectedSegmentIndex;
    GeminiNetworkMode mode = (modeIdx == 1) ? GeminiNetworkModeDirectRPC : GeminiNetworkModeProxy;
    [d setInteger:(NSInteger)mode forKey:kGeminiPrefMode];

    NSString *proxyText = self.proxyField.text;
    if (proxyText && [proxyText length] > 0) {
        [d setObject:proxyText forKey:kGeminiPrefProxyURL];
    }

    NSString *apiText = self.apiKeyField.text;
    if (apiText) { [d setObject:apiText forKey:kGeminiPrefAPIKey]; }

    NSString *cookieText = self.cookieField.text;
    if (cookieText) { [d setObject:cookieText forKey:kGeminiPrefSessionCookie]; }

    NSString *snlmText = self.snlmField.text;
    if (snlmText) { [d setObject:snlmText forKey:kGeminiPrefSNlM0e]; }

    NSString *modelText = self.modelField.text;
    if (modelText && [modelText length] > 0) {
        [d setObject:modelText forKey:kGeminiPrefModel];
    }

    [d synchronize];

    /* Обновляем сетевой клиент */
    [self.networkClient setMode:mode];
    [self.networkClient reloadSettings];

    /* Уведомляем делегата */
    if (self.delegate &&
        [self.delegate respondsToSelector:@selector(settingsViewControllerDidSave:)]) {
        [self.delegate settingsViewControllerDidSave:self];
    }

    /* Закрываем экран */
    [self.navigationController popViewControllerAnimated:YES];
}

/* ── Отмена ── */
- (void)cancelSettings
{
    [self.view endEditing:YES];
    [self.navigationController popViewControllerAnimated:YES];
}

/* ── UITextFieldDelegate ── */
- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

/* ── Клавиатура ── */
- (void)_keyboardWillShow:(NSNotification *)note
{
    NSDictionary *info = [note userInfo];
    NSValue *kbFrame   = [info objectForKey:UIKeyboardFrameEndUserInfoKey];
    CGRect  kbRect     = [kbFrame CGRectValue];
    /* Конвертируем из экранных координат в координаты scrollView */
    CGRect kbInView = [self.scrollView convertRect:kbRect fromView:nil];
    CGFloat bottomOverlap = CGRectGetMaxY(self.scrollView.bounds) - CGRectGetMinY(kbInView);
    if (bottomOverlap > 0) {
        UIEdgeInsets ins = self.scrollView.contentInset;
        ins.bottom = bottomOverlap;
        self.scrollView.contentInset           = ins;
        self.scrollView.scrollIndicatorInsets  = ins;
    }
}

- (void)_keyboardWillHide:(NSNotification *)note
{
    UIEdgeInsets ins = self.scrollView.contentInset;
    ins.bottom = 0;
    self.scrollView.contentInset           = ins;
    self.scrollView.scrollIndicatorInsets  = ins;
}

/* ── Tap to dismiss ── */
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self.view endEditing:YES];
}

@end
