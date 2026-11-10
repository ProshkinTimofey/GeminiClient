/*
 * GeminiNetworkClient.m — GeminiClient (Theos, MRC, iOS 3.0+)
 *
 * ═══ ВАЖНО: iOS 3.0 ограничения ═══════════════════════════════════════════
 *   • Нет блоков ^{}            → только делегаты и performSelector...
 *   • Нет GCD dispatch_async    → performSelectorInBackground:withObject:
 *   • Нет NSJSONSerialization   → cJSON (C99, работает с iOS 1.0)
 *   • Нет @autoreleasepool {}   → NSAutoreleasePool alloc/init/release
 *   • Нет weakSelf / __weak     → __unsafe_unretained (или просто assign)
 *   • NSURLConnection делегат   → connectionDidFinishLoading / didReceiveData
 *   • UILineBreakModeWordWrap   → вместо NSLineBreakByWordWrapping
 * ══════════════════════════════════════════════════════════════════════════
 */

#import "GeminiNetworkClient.h"
#import "cJSON.h"

#include <string.h>
#include <stdlib.h>

/* ── Строки ключей NSUserDefaults ── */
NSString * const kGeminiPrefMode           = @"GeminiNetworkMode";
NSString * const kGeminiPrefProxyURL       = @"GeminiProxyURL";
NSString * const kGeminiPrefAPIKey         = @"GeminiAPIKey";
NSString * const kGeminiPrefSessionCookie  = @"GeminiSessionCookie";
NSString * const kGeminiPrefSNlM0e        = @"GeminiSNlM0e";
NSString * const kGeminiPrefModel          = @"GeminiModel";

/* ── Значения по умолчанию ── */
static NSString * const kDefaultProxyURL   = @"http://your-proxy.example.com/api/chat";
static NSString * const kDefaultModel      = @"gemini-2.0-flash";

/* ══════════════════════════════════════════════════════════════════════════
 * Вспомогательные C-функции (cJSON)
 * ══════════════════════════════════════════════════════════════════════════ */

/*
 * gemini_json_escape — экранирует строку для вставки в JSON вручную.
 * Нужна для Режима B (f.req), где мы строим JSON без NSJSONSerialization.
 * Возвращает malloc-строку — вызывающий должен free().
 */
static char *gemini_json_escape(const char *src)
{
    if (!src) { return strdup(""); }

    size_t len    = strlen(src);
    size_t buflen = len * 6 + 3; /* worst case: каждый символ → \uXXXX */
    char  *buf    = (char *)malloc(buflen);
    if (!buf) { return strdup(""); }

    char  *dst = buf;
    *dst++ = '"';

    while (*src) {
        unsigned char c = (unsigned char)*src++;
        switch (c) {
            case '"':  *dst++ = '\\'; *dst++ = '"';  break;
            case '\\': *dst++ = '\\'; *dst++ = '\\'; break;
            case '\n': *dst++ = '\\'; *dst++ = 'n';  break;
            case '\r': *dst++ = '\\'; *dst++ = 'r';  break;
            case '\t': *dst++ = '\\'; *dst++ = 't';  break;
            default:
                if (c < 0x20) {
                    dst += sprintf(dst, "\\u%04x", c);
                } else {
                    *dst++ = (char)c;
                }
                break;
        }
    }
    *dst++ = '"';
    *dst   = '\0';
    return buf;
}

/*
 * gemini_strip_prefix — снимает )]}'  префикс Google RPC и возвращает
 * указатель на первый символ после него. Не меняет входной буфер.
 * Если префикс не найден — возвращает src как есть.
 */
static const char *gemini_strip_prefix(const char *src)
{
    static const char prefix[] = ")]}'\n";
    if (src && strncmp(src, prefix, strlen(prefix)) == 0) {
        return src + strlen(prefix);
    }
    /* Иногда одна строка: )]}'без \n */
    if (src && strncmp(src, ")]}'", 4) == 0) {
        return src + 4;
    }
    return src;
}

/*
 * gemini_parse_proxy_reply — разбирает JSON из Режима A:
 *   {"reply": "...", "error": "..."}
 * Возвращает retained NSString или nil при ошибке.
 */
static NSString *gemini_parse_proxy_reply(const char *jsonBytes, NSError **outError)
{
    cJSON *root = cJSON_Parse(jsonBytes);
    if (!root) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"GeminiParse"
                                           code:1001
                                       userInfo:[NSDictionary dictionaryWithObject:@"Invalid JSON from proxy"
                                                                            forKey:NSLocalizedDescriptionKey]];
        }
        return nil;
    }

    /* Проверяем поле error */
    cJSON *errNode = cJSON_GetObjectItem(root, "error");
    if (errNode && cJSON_IsString(errNode) && errNode->valuestring && strlen(errNode->valuestring) > 0) {
        NSString *errStr = [[NSString alloc] initWithUTF8String:errNode->valuestring];
        if (outError) {
            *outError = [NSError errorWithDomain:@"GeminiProxy"
                                           code:1002
                                       userInfo:[NSDictionary dictionaryWithObject:errStr
                                                                            forKey:NSLocalizedDescriptionKey]];
        }
        [errStr release];
        cJSON_Delete(root);
        return nil;
    }

    cJSON *replyNode = cJSON_GetObjectItem(root, "reply");
    if (!replyNode || !cJSON_IsString(replyNode) || !replyNode->valuestring) {
        /* Fallback: попробуем "text", "content", "candidates[0].content.parts[0].text" */
        cJSON *candidatesNode = cJSON_GetObjectItem(root, "candidates");
        if (cJSON_IsArray(candidatesNode)) {
            cJSON *c0 = cJSON_GetArrayItem(candidatesNode, 0);
            cJSON *contentNode = cJSON_GetObjectItem(c0, "content");
            cJSON *partsNode   = cJSON_GetObjectItem(contentNode, "parts");
            cJSON *p0          = cJSON_GetArrayItem(partsNode, 0);
            cJSON *textNode    = cJSON_GetObjectItem(p0, "text");
            if (textNode && cJSON_IsString(textNode) && textNode->valuestring) {
                NSString *text = [[NSString alloc] initWithUTF8String:textNode->valuestring];
                cJSON_Delete(root);
                return [text autorelease];
            }
        }

        if (outError) {
            *outError = [NSError errorWithDomain:@"GeminiParse"
                                           code:1003
                                       userInfo:[NSDictionary dictionaryWithObject:@"No 'reply' field in JSON"
                                                                            forKey:NSLocalizedDescriptionKey]];
        }
        cJSON_Delete(root);
        return nil;
    }

    NSString *result = [[NSString alloc] initWithUTF8String:replyNode->valuestring];
    cJSON_Delete(root);
    return [result autorelease];
}

/*
 * gemini_parse_rpc_reply — разбирает потоковый ответ batchexecute / StreamGenerate.
 *
 * Формат Google RPC:
 *   )]}'\n
 *   183\n
 *   [[["wrb.fr","StreamGenerate","[[\"...JSON...\"]]",null,null,null,"generic"]]\n
 *   27\n
 *   [[["e",4,null,null,129]]]\n
 *
 * Алгоритм:
 *   1. Снимаем )]}'  префикс.
 *   2. Разбиваем по строкам.
 *   3. Ищем строки, начинающиеся с '[[['.
 *   4. Парсим внешний массив через cJSON.
 *   5. В payload[0][0][2] лежит вложенный JSON-строкой — парсим его.
 *   6. В нём ищем поле с текстом ответа (обычно структура model-turn / parts).
 *
 * Это точный аналог Swift-парсера extractPayloads из GeminiRPCClient.swift.
 */
static NSString *gemini_parse_rpc_reply(const char *rawBytes, NSError **outError)
{
    if (!rawBytes || strlen(rawBytes) == 0) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"GeminiParse"
                                           code:2001
                                       userInfo:[NSDictionary dictionaryWithObject:@"Empty RPC response"
                                                                            forKey:NSLocalizedDescriptionKey]];
        }
        return nil;
    }

    /* 1. Снять префикс */
    const char *data = gemini_strip_prefix(rawBytes);

    /* 2. Копируем в рабочий буфер для posrfixstrtok */
    char *buf = strdup(data);
    if (!buf) { return nil; }

    NSMutableArray *candidates = [[NSMutableArray alloc] init];

    /* 3. Итерируем по строкам (strsep / strtok_r) */
    char *saveptr = NULL;
    char *line    = NULL;

    /* strtok_r — POSIX, доступен с самых ранних iOS */
    line = strtok_r(buf, "\n", &saveptr);
    while (line != NULL) {
        /* Пропускаем строки-длины (chunked transfer: "183", "27" ...) */
        if (line[0] != '[') {
            line = strtok_r(NULL, "\n", &saveptr);
            continue;
        }

        /* Парсим внешний массив */
        cJSON *outer = cJSON_Parse(line);
        if (!outer || !cJSON_IsArray(outer)) {
            if (outer) cJSON_Delete(outer);
            line = strtok_r(NULL, "\n", &saveptr);
            continue;
        }

        /* outer = [ [ [ "wrb.fr", "StreamGenerate", "PAYLOAD_JSON", ... ] ] ] */
        cJSON *inner0 = cJSON_GetArrayItem(outer, 0);
        cJSON *inner1 = cJSON_GetArrayItem(inner0, 0);
        cJSON *opName = cJSON_GetArrayItem(inner1, 1); /* "StreamGenerate" */
        cJSON *payload = cJSON_GetArrayItem(inner1, 2); /* JSON-строка */

        BOOL isStreamGenerate = (opName && cJSON_IsString(opName)
                                 && opName->valuestring
                                 && strcmp(opName->valuestring, "StreamGenerate") == 0);

        if (isStreamGenerate && payload && cJSON_IsString(payload) && payload->valuestring) {
            /* payload->valuestring — это строка, содержащая JSON */
            cJSON *inner = cJSON_Parse(payload->valuestring);
            if (inner) {
                /*
                 * Структура ответа Gemini StreamGenerate:
                 * [
                 *   [ [ {"text":"..."}, ... ], ... ],  <-- [0][0]  parts
                 *   ...
                 * ]
                 * Либо (новый формат):
                 * [ [[ {"1": {"1": "текст ответа"} }]] ]
                 *
                 * Поднимаемся через arr[0][0][0]["text"] или arr[0][0]["1"]["1"]
                 */
                cJSON *a0 = cJSON_GetArrayItem(inner, 0);
                cJSON *a1 = cJSON_GetArrayItem(a0, 0);
                cJSON *a2 = cJSON_GetArrayItem(a1, 0);

                /* Формат A: { "text": "..." } */
                cJSON *textNode = cJSON_GetObjectItem(a2, "text");
                if (!textNode || !cJSON_IsString(textNode)) {
                    /* Формат B: { "1": { "1": "..." } } */
                    cJSON *f1 = cJSON_GetObjectItem(a2, "1");
                    textNode  = cJSON_GetObjectItem(f1, "1");
                }

                if (textNode && cJSON_IsString(textNode) && textNode->valuestring) {
                    NSString *chunk = [[NSString alloc] initWithUTF8String:textNode->valuestring];
                    [candidates addObject:chunk];
                    [chunk release];
                }
                cJSON_Delete(inner);
            }
        }

        cJSON_Delete(outer);
        line = strtok_r(NULL, "\n", &saveptr);
    }

    free(buf);

    /* Берём последний (наиболее полный) кандидат — аналог payloads.reversed() */
    NSString *result = nil;
    if ([candidates count] > 0) {
        result = [[candidates lastObject] retain];
    } else {
        if (outError) {
            *outError = [NSError errorWithDomain:@"GeminiParse"
                                           code:2002
                                       userInfo:[NSDictionary dictionaryWithObject:@"No StreamGenerate payload found"
                                                                            forKey:NSLocalizedDescriptionKey]];
        }
    }

    [candidates release];
    return [result autorelease];
}

/* ══════════════════════════════════════════════════════════════════════════
 * GeminiNetworkOperation
 * Один асинхронный NSURLConnection-запрос. Callback — через делегат на main thread.
 * ══════════════════════════════════════════════════════════════════════════ */

@implementation GeminiNetworkOperation

@synthesize responseData = _responseData;
@synthesize connection   = _connection;
@synthesize delegate     = _delegate;
@synthesize client       = _client;
@synthesize mode         = _mode;

- (id)init
{
    self = [super init];
    if (self) {
        _responseData = [[NSMutableData alloc] init];
        _finished     = NO;
    }
    return self;
}

- (void)dealloc
{
    [_responseData release];
    [_connection   release];
    [super dealloc];
}

- (void)startWithRequest:(NSURLRequest *)request
{
    NSURLConnection *conn = [[NSURLConnection alloc]
                              initWithRequest:request
                                     delegate:self
                             startImmediately:YES];
    self.connection = conn;
    [conn release];
}

- (void)cancel
{
    [self.connection cancel];
    _finished = YES;
}

/* ── NSURLConnectionDelegate (iOS 3.0 API) ── */

/* iOS 3.0: connection:didReceiveResponse: */
- (void)connection:(NSURLConnection *)connection
didReceiveResponse:(NSURLResponse *)response
{
    [self.responseData setLength:0];
}

/* iOS 3.0: connection:didReceiveData: */
- (void)connection:(NSURLConnection *)connection
    didReceiveData:(NSData *)data
{
    [self.responseData appendData:data];
}

/* iOS 3.0: connectionDidFinishLoading: */
- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    if (_finished) { return; }
    _finished = YES;

    /* Копируем данные и делегата перед переходом на фоновый поток */
    NSData *rawData     = [self.responseData copy];
    GeminiNetworkMode m = self.mode;

    /* Парсинг на фоновом потоке через performSelectorInBackground (iOS 3.0+) */
    NSDictionary *params = [[NSDictionary alloc] initWithObjectsAndKeys:
                             rawData, @"data",
                             [NSNumber numberWithInt:(int)m], @"mode",
                             nil];
    [rawData release];
    [self performSelectorInBackground:@selector(_parseAndDispatch:) withObject:params];
    [params release];
}

- (void)_parseAndDispatch:(NSDictionary *)params
{
    /* Создаём autorelease pool — фоновый поток, iOS 3.0+ */
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSData            *rawData = [params objectForKey:@"data"];
    GeminiNetworkMode  m       = (GeminiNetworkMode)[[params objectForKey:@"mode"] intValue];

    /* Конвертируем байты в строку UTF-8 */
    NSString *bodyStr = [[NSString alloc] initWithData:rawData encoding:NSUTF8StringEncoding];
    if (!bodyStr) {
        bodyStr = [[NSString alloc] initWithData:rawData encoding:NSISOLatin1StringEncoding];
    }
    const char *utf8 = [bodyStr UTF8String];

    NSError  *parseError = nil;
    NSString *reply      = nil;

    if (m == GeminiNetworkModeProxy) {
        reply = gemini_parse_proxy_reply(utf8, &parseError);
    } else {
        reply = gemini_parse_rpc_reply(utf8, &parseError);
    }
    [bodyStr release];

    if (reply) {
        /* retain, чтобы дожил до main thread */
        [reply retain];
        [self performSelectorOnMainThread:@selector(_callDelegateWithReply:)
                               withObject:reply
                            waitUntilDone:NO];
        [reply release];
    } else {
        NSError *err = parseError ? parseError
                                  : [NSError errorWithDomain:@"GeminiParse"
                                                        code:9999
                                                    userInfo:[NSDictionary dictionaryWithObject:@"Unknown parse error"
                                                                                         forKey:NSLocalizedDescriptionKey]];
        [err retain];
        [self performSelectorOnMainThread:@selector(_callDelegateWithError:)
                               withObject:err
                            waitUntilDone:NO];
        [err release];
    }

    [pool release];
}

- (void)_callDelegateWithReply:(NSString *)reply
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(networkClient:didReceiveReply:)]) {
        [self.delegate networkClient:self.client didReceiveReply:reply];
    }
}

- (void)_callDelegateWithError:(NSError *)error
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(networkClient:didFailWithError:)]) {
        [self.delegate networkClient:self.client didFailWithError:error];
    }
}

/* iOS 3.0: connection:didFailWithError: */
- (void)connection:(NSURLConnection *)connection
  didFailWithError:(NSError *)error
{
    if (_finished) { return; }
    _finished = YES;

    if (self.delegate && [self.delegate respondsToSelector:@selector(networkClient:didFailWithError:)]) {
        [self.delegate networkClient:self.client didFailWithError:error];
    }
}

/* iOS 3.0: Игнорируем невалидные сертификаты (нужно для прокси по HTTP) */
- (BOOL)connection:(NSURLConnection *)connection
canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace
{
    return [protectionSpace.authenticationMethod
            isEqualToString:NSURLAuthenticationMethodServerTrust];
}

- (void)connection:(NSURLConnection *)connection
didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if ([challenge.protectionSpace.authenticationMethod
         isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        /* Принимаем любой сертификат — для разработки / прокси */
        [challenge.sender useCredential:
            [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]
         forAuthenticationChallenge:challenge];
    } else {
        [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
    }
}

@end

/* ══════════════════════════════════════════════════════════════════════════
 * GeminiNetworkClient
 * ══════════════════════════════════════════════════════════════════════════ */

@implementation GeminiNetworkClient

@synthesize mode          = _mode;
@synthesize proxyURL      = _proxyURL;
@synthesize apiKey        = _apiKey;
@synthesize sessionCookie = _sessionCookie;
@synthesize snlm0e        = _snlm0e;
@synthesize model         = _model;

- (id)init
{
    self = [super init];
    if (self) {
        _currentOperation = nil;
        [self reloadSettings];
    }
    return self;
}

- (void)dealloc
{
    [_currentOperation cancel];
    [_currentOperation release];
    [_proxyURL      release];
    [_apiKey        release];
    [_sessionCookie release];
    [_snlm0e       release];
    [_model         release];
    [super dealloc];
}

- (void)reloadSettings
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    NSInteger storedMode = [d integerForKey:kGeminiPrefMode];
    _mode = (GeminiNetworkMode)storedMode;

    NSString *pURL = [d stringForKey:kGeminiPrefProxyURL];
    self.proxyURL  = (pURL && [pURL length] > 0) ? pURL : kDefaultProxyURL;

    NSString *key  = [d stringForKey:kGeminiPrefAPIKey];
    self.apiKey    = key ? key : @"";

    NSString *sess = [d stringForKey:kGeminiPrefSessionCookie];
    self.sessionCookie = sess ? sess : @"";

    NSString *snl  = [d stringForKey:kGeminiPrefSNlM0e];
    self.snlm0e    = snl ? snl : @"";

    NSString *mdl  = [d stringForKey:kGeminiPrefModel];
    self.model     = (mdl && [mdl length] > 0) ? mdl : kDefaultModel;
}

- (GeminiNetworkMode)currentMode
{
    return _mode;
}

- (void)setMode:(GeminiNetworkMode)mode
{
    _mode = mode;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:(NSInteger)mode forKey:kGeminiPrefMode];
    [d synchronize];
}

- (void)cancelCurrentRequest
{
    if (_currentOperation) {
        [_currentOperation cancel];
        [_currentOperation release];
        _currentOperation = nil;
    }
}

/* ══ Режим A: Proxy / REST API ═══════════════════════════════════════════ */

/*
 * Строим JSON-тело вручную через cJSON (нет NSJSONSerialization на iOS 3-4).
 *
 * Для Gemini REST (generativelanguage.googleapis.com):
 * {
 *   "contents": [{"parts":[{"text":"PROMPT"}]}]
 * }
 *
 * Для кастомного прокси (упрощённый формат):
 * {
 *   "prompt": "PROMPT",
 *   "model":  "gemini-2.0-flash"
 * }
 *
 * Мы отправляем оба поля — прокси может использовать любое.
 */
- (NSURLRequest *)_buildProxyRequestForPrompt:(NSString *)prompt
{
    [self reloadSettings];

    /* ── Строим JSON через cJSON ── */
    cJSON *root = cJSON_CreateObject();

    /* Поле "prompt" (для простых прокси) */
    cJSON_AddStringToObject(root, "prompt", [prompt UTF8String]);

    /* Поле "model" */
    cJSON_AddStringToObject(root, "model", [self.model UTF8String]);

    /* Поле "contents" (Gemini REST API формат) */
    cJSON *contents = cJSON_CreateArray();
    cJSON *turn     = cJSON_CreateObject();
    cJSON *parts    = cJSON_CreateArray();
    cJSON *part     = cJSON_CreateObject();
    cJSON_AddStringToObject(part, "text", [prompt UTF8String]);
    cJSON_AddItemToArray(parts, part);
    cJSON_AddItemToObject(turn, "parts", parts);
    cJSON_AddItemToArray(contents, turn);
    cJSON_AddItemToObject(root, "contents", contents);

    char *jsonStr = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);

    NSData *body = [NSData dataWithBytes:jsonStr length:strlen(jsonStr)];
    free(jsonStr);

    /* ── URL ── */
    NSString *urlStr = self.proxyURL;

    /* Если задан API-ключ и URL похож на googleapis.com — добавляем key */
    if ([self.apiKey length] > 0 &&
        [urlStr rangeOfString:@"googleapis.com"].location != NSNotFound) {
        urlStr = [urlStr stringByAppendingFormat:@"?key=%@", self.apiKey];
    }

    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) { return nil; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:30.0];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[body length]]
       forHTTPHeaderField:@"Content-Length"];

    /* API-ключ в заголовке (если не в URL) */
    if ([self.apiKey length] > 0 &&
        [urlStr rangeOfString:@"googleapis.com"].location == NSNotFound) {
        [req setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey]
           forHTTPHeaderField:@"Authorization"];
    }

    [req setHTTPBody:body];
    return req;
}

/* ══ Режим B: Прямой batchexecute ═══════════════════════════════════════ */

/*
 * SNlM0e — одноразовый CSRF-токен Gemini.
 * В iOS 15.8 его можно достать из cookie / из страницы gemini.google.com.
 * На iOS 3.0 придётся вводить вручную (Settings).
 *
 * Формат f.req (точный аналог GeminiRPCClient.swift buildFReq):
 * [[[null, "[[\\"PROMPT\\", null, null, null, null, null, null, null, [], null, null, null, [], []]]", null, "StreamGenerate"]]]
 *
 * URL: https://gemini.google.com/u/0/_/BardChatUi/data/batchexecute
 *      ?rpcids=StreamGenerate&source-path=/&f.sid=-XXX&bl=BOOT_LABEL&rt=c
 */
- (NSURLRequest *)_buildRPCRequestForPrompt:(NSString *)prompt
{
    [self reloadSettings];

    /* ── Строим f.req ── */
    char *escapedPrompt = gemini_json_escape([prompt UTF8String]);

    /*
     * Внутренний массив Gemini (prompt как первый элемент):
     * [["PROMPT", null, null, null, null, null, null, null, [], null, null, null, [], []]]
     */
    char *innerJSON = NULL;
    asprintf(&innerJSON, "[[%s,null,null,null,null,null,null,null,[],null,null,null,[],[]]]",
             escapedPrompt);
    free(escapedPrompt);

    /*
     * Экранируем innerJSON для вставки в строку f.req
     * (innerJSON сам является JSON-строкой внутри внешнего массива)
     */
    char *escapedInner = gemini_json_escape(innerJSON);
    free(innerJSON);

    /*
     * Финальный f.req:
     * [[[null,"ESCAPED_INNER",null,"StreamGenerate"]]]
     */
    char *fReqJSON = NULL;
    asprintf(&fReqJSON, "[[[null,%s,null,\"StreamGenerate\"]]]", escapedInner);
    free(escapedInner);

    /* URL-encode f.req (нужно заменить & = + пробелы) */
    NSString *fReqStr = [NSString stringWithUTF8String:fReqJSON];
    free(fReqJSON);

    /* iOS 3.0 совместимый URL-encode без блоков */
    NSString *fReqEncoded = (NSString *)CFURLCreateStringByAddingPercentEscapes(
        kCFAllocatorDefault,
        (CFStringRef)fReqStr,
        NULL,
        (CFStringRef)@"!*'();:@&=+$,/?%#[]",
        kCFStringEncodingUTF8
    );

    /* Тело POST: f.req=... */
    NSString *bodyStr = [NSString stringWithFormat:@"f.req=%@&at=%@",
                         fReqEncoded,
                         [self.snlm0e length] > 0 ? self.snlm0e : @""];
    [fReqEncoded release]; /* CFURLCreateStringByAddingPercentEscapes возвращает retain+1 */

    NSData *body = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];

    /* ── URL ── */
    NSString *urlStr = @"https://gemini.google.com/u/0/_/BardChatUi/data/batchexecute"
                       @"?rpcids=StreamGenerate&source-path=/&rt=c";

    NSURL *url = [NSURL URLWithString:urlStr];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:30.0];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[body length]]
       forHTTPHeaderField:@"Content-Length"];

    /* ── Куки ── */
    if ([self.sessionCookie length] > 0) {
        NSString *cookieHeader = [NSString stringWithFormat:@"__Secure-1PSID=%@",
                                  self.sessionCookie];
        [req setValue:cookieHeader forHTTPHeaderField:@"Cookie"];
    }

    /* ── User-Agent ── */
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 15_8 like Mac OS X) "
                  @"AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6.1 "
                  @"Mobile/15E148 Safari/604.1"
       forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"https://gemini.google.com/" forHTTPHeaderField:@"Referer"];
    [req setValue:@"same-origin"                forHTTPHeaderField:@"Sec-Fetch-Site"];
    [req setValue:@"empty"                      forHTTPHeaderField:@"Sec-Fetch-Mode"];

    [req setHTTPBody:body];
    return req;
}

/* ══ Публичный API ═══════════════════════════════════════════════════════ */

- (void)sendPrompt:(NSString *)prompt
          delegate:(id<GeminiNetworkDelegate>)delegate
{
    if (!prompt || [prompt length] == 0) {
        NSError *err = [NSError errorWithDomain:@"GeminiClient"
                                           code:1
                                       userInfo:[NSDictionary dictionaryWithObject:@"Empty prompt"
                                                                            forKey:NSLocalizedDescriptionKey]];
        if (delegate) {
            [delegate networkClient:self didFailWithError:err];
        }
        return;
    }

    /* Отменить предыдущий запрос */
    [self cancelCurrentRequest];

    /* Выбираем режим и строим запрос */
    NSURLRequest *req = nil;
    if (_mode == GeminiNetworkModeProxy) {
        req = [self _buildProxyRequestForPrompt:prompt];
    } else {
        req = [self _buildRPCRequestForPrompt:prompt];
    }

    if (!req) {
        NSError *err = [NSError errorWithDomain:@"GeminiClient"
                                           code:2
                                       userInfo:[NSDictionary dictionaryWithObject:@"Failed to build URL request (check settings)"
                                                                            forKey:NSLocalizedDescriptionKey]];
        if (delegate) {
            [delegate networkClient:self didFailWithError:err];
        }
        return;
    }

    /* Создаём операцию */
    GeminiNetworkOperation *op = [[GeminiNetworkOperation alloc] init];
    op.delegate = delegate;
    op.client   = self;
    op.mode     = _mode;
    _currentOperation = op; /* не release — мы держим ссылку */

    NSLog(@"[GeminiNet] Sending prompt via %@ mode: %@",
          (_mode == GeminiNetworkModeProxy) ? @"Proxy" : @"DirectRPC",
          prompt);

    [op startWithRequest:req];
}

@end
