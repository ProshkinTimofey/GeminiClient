/*
 * GeminiNetworkClient.h — GeminiClient (Theos, MRC, iOS 3.0+)
 *
 * Сетевой движок с двумя переключаемыми режимами:
 *
 *   GeminiNetworkModeProxy     (Режим A):
 *     Отправляет POST /api/chat на кастомный HTTP-шлюз (Cloudflare Worker,
 *     Python-сервер, или прямо на generativelanguage.googleapis.com с API-ключом).
 *     Работает даже на iOS 3.0 через plain HTTP + NSURLConnection.
 *     JSON: {"prompt": "...", "model": "gemini-1.5-flash"}
 *     Ответ: {"reply": "..."}
 *
 *   GeminiNetworkModeDirectRPC (Режим B):
 *     Прямой batchexecute / StreamGenerate к gemini.google.com.
 *     Требует TLS 1.2+ (iOS 5.0+ или TLSFix-твик на старых).
 *     Аутентификация: Cookie __Secure-1PSID + SNlM0e токен.
 *     Ответ: prefix )]}'  затем JSON — парсим через cJSON.
 *
 * iOS 3.0 совместимость:
 *   - Нет блоков (^). Всё через делегаты.
 *   - Нет GCD. Фоновый поток: performSelectorInBackground:withObject:
 *   - Нет NSJSONSerialization. Только cJSON.
 *   - Явный @synthesize, ручной dealloc.
 *   - NSURLConnection с делегатом NSURLConnectionDelegate.
 */

#import <Foundation/Foundation.h>

/* ── Режимы работы ── */
typedef enum {
    GeminiNetworkModeProxy     = 0,  /* Режим A: через HTTP-шлюз */
    GeminiNetworkModeDirectRPC = 1   /* Режим B: прямой batchexecute */
} GeminiNetworkMode;

/* ── Имена ключей NSUserDefaults ── */
extern NSString * const kGeminiPrefMode;        /* NSInteger: GeminiNetworkMode */
extern NSString * const kGeminiPrefProxyURL;    /* NSString: URL шлюза */
extern NSString * const kGeminiPrefAPIKey;      /* NSString: Gemini API ключ */
extern NSString * const kGeminiPrefSessionCookie; /* NSString: __Secure-1PSID */
extern NSString * const kGeminiPrefSNlM0e;     /* NSString: SNlM0e токен */
extern NSString * const kGeminiPrefModel;       /* NSString: модель */

/* ── Делегат результата ── */
@class GeminiNetworkClient;

@protocol GeminiNetworkDelegate <NSObject>
@required
/* Вызывается на главном потоке */
- (void)networkClient:(GeminiNetworkClient *)client didReceiveReply:(NSString *)reply;
- (void)networkClient:(GeminiNetworkClient *)client didFailWithError:(NSError *)error;
@end

/* ════════════════════════════════════════════════════════════════════════════ */

/*
 * GeminiNetworkOperation — один асинхронный запрос.
 * Создаётся внутри GeminiNetworkClient, держит NSURLConnection.
 * Когда получен полный ответ — вызывает callback через performSelectorOnMainThread:.
 *
 * Мы используем отдельный объект-операцию, чтобы GeminiNetworkClient
 * не удерживал NSURLConnection (retain-цикл), и поддерживать очередь запросов.
 */
@interface GeminiNetworkOperation : NSObject <NSURLConnectionDelegate>
{
    NSMutableData         *_responseData;
    NSURLConnection       *_connection;

    /* Слабая ссылка на делегат (не retain, чтобы не было цикла) */
    id<GeminiNetworkDelegate> _delegate; /* __unsafe_unretained в MRC */

    /* Владелец для обратного вызова */
    GeminiNetworkClient   *_client;      /* __unsafe_unretained */

    GeminiNetworkMode      _mode;
    BOOL                   _finished;
}

@property (nonatomic, retain) NSMutableData   *responseData;
@property (nonatomic, retain) NSURLConnection *connection;

/* Не retain — делегат живёт снаружи и должен pережить операцию */
@property (nonatomic, assign) id<GeminiNetworkDelegate>  delegate;
@property (nonatomic, assign) GeminiNetworkClient       *client;
@property (nonatomic, assign) GeminiNetworkMode          mode;

/* Запускает соединение */
- (void)startWithRequest:(NSURLRequest *)request;
- (void)cancel;

@end

/* ════════════════════════════════════════════════════════════════════════════ */

@interface GeminiNetworkClient : NSObject
{
    GeminiNetworkMode  _mode;

    /* Настройки (читаем из NSUserDefaults при каждом запросе) */
    NSString          *_proxyURL;
    NSString          *_apiKey;
    NSString          *_sessionCookie;
    NSString          *_snlm0e;
    NSString          *_model;

    /* Текущая операция (одна за раз; добавить очередь в Шаге 4) */
    GeminiNetworkOperation *_currentOperation;
}

@property (nonatomic, assign) GeminiNetworkMode mode;
@property (nonatomic, retain) NSString *proxyURL;
@property (nonatomic, retain) NSString *apiKey;
@property (nonatomic, retain) NSString *sessionCookie;
@property (nonatomic, retain) NSString *snlm0e;
@property (nonatomic, retain) NSString *model;

/* Загружает настройки из NSUserDefaults */
- (void)reloadSettings;

/* Возвращает текущий режим */
- (GeminiNetworkMode)currentMode;

/* Явно задаёт режим (и сохраняет в NSUserDefaults) */
- (void)setMode:(GeminiNetworkMode)mode;

/*
 * Отправить промпт. Результат придёт через делегата на главном потоке.
 * delegate: объект, реализующий GeminiNetworkDelegate.
 */
- (void)sendPrompt:(NSString *)prompt
          delegate:(id<GeminiNetworkDelegate>)delegate;

/* Отменить текущий запрос */
- (void)cancelCurrentRequest;

@end
