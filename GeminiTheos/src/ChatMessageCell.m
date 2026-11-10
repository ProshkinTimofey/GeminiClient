/*
 * ChatMessageCell.m — GeminiClient (Theos, MRC, iOS 3.0+)
 */

#import "ChatMessageCell.h"

/* ══════════════════════════════════════════════════════════════════════════
 * Вспомогательная C-функция: цвет баббла пользователя
 * ══════════════════════════════════════════════════════════════════════════ */

static UIColor *kUserBubbleColor(void)
{
    /* Синий — стандарт «отправитель» в iOS Messaging */
    return [UIColor colorWithRed:0.14f green:0.49f blue:0.96f alpha:1.0f];
}

static UIColor *kBotBubbleColor(void)
{
    /* Тёмно-серый — ответ AI */
    return [UIColor colorWithRed:0.22f green:0.22f blue:0.26f alpha:1.0f];
}

static UIColor *kUserTextColor(void)   { return [UIColor whiteColor]; }
static UIColor *kBotTextColor(void)    { return [UIColor whiteColor]; }
static UIColor *kBgColor(void)
{
    return [UIColor colorWithRed:0.07f green:0.07f blue:0.09f alpha:1.0f];
}

/*
 * gemini_make_bubble_image — рисует скруглённый прямоугольник программно
 * и возвращает stretchable UIImage.
 * Используем CoreGraphics (iOS 2.0+). Нет UIBezierPath на iOS 3.0
 * (UIBezierPath добавлен в iOS 3.2 / iPad SDK, но реально на 4.0 для iPhone).
 */
static UIImage *gemini_make_bubble_image(UIColor *fillColor,
                                         CGFloat  cornerRadius,
                                         CGFloat  size)
{
    /* Рисуем квадрат size×size, потом стретчим */
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0f);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    CGRect rect = CGRectMake(0, 0, size, size);
    CGFloat r = cornerRadius;

    /* Рисуем скруглённый прямоугольник через CGPath (iOS 2.0+) */
    CGContextBeginPath(ctx);
    CGContextMoveToPoint   (ctx, r, 0);
    CGContextAddLineToPoint(ctx, size - r, 0);
    CGContextAddArcToPoint (ctx, size, 0,    size, r,      r);
    CGContextAddLineToPoint(ctx, size, size - r);
    CGContextAddArcToPoint (ctx, size, size, size - r, size, r);
    CGContextAddLineToPoint(ctx, r, size);
    CGContextAddArcToPoint (ctx, 0, size, 0, size - r, r);
    CGContextAddLineToPoint(ctx, 0, r);
    CGContextAddArcToPoint (ctx, 0, 0,    r, 0,         r);
    CGContextClosePath(ctx);

    CGFloat red, green, blue, alpha;
    [fillColor getRed:&red green:&green blue:&blue alpha:&alpha];
    CGContextSetRGBFillColor(ctx, red, green, blue, alpha);
    CGContextFillPath(ctx);

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    /* stretchableImageWithLeftCapWidth:topCapHeight: — iOS 2.0+ */
    NSInteger cap = (NSInteger)cornerRadius;
    return [img stretchableImageWithLeftCapWidth:cap topCapHeight:cap];
}

/* ══════════════════════════════════════════════════════════════════════════
 * ChatMessage
 * ══════════════════════════════════════════════════════════════════════════ */

@implementation ChatMessage

@synthesize text      = _text;
@synthesize isUser    = _isUser;
@synthesize timestamp = _timestamp;

+ (ChatMessage *)messageWithText:(NSString *)text isUser:(BOOL)isUser
{
    ChatMessage *m = [[[ChatMessage alloc] init] autorelease];
    m.text      = text;
    m.isUser    = isUser;
    m.timestamp = [NSDate date];
    return m;
}

- (void)dealloc
{
    [_text      release];
    [_timestamp release];
    [super dealloc];
}

@end

/* ══════════════════════════════════════════════════════════════════════════
 * ChatMessageCell
 * ══════════════════════════════════════════════════════════════════════════ */

@implementation ChatMessageCell

@synthesize messageLabel = _messageLabel;
@synthesize bubbleView   = _bubbleView;
@synthesize avatarView   = _avatarView;
@synthesize isUser       = _isUser;

- (id)initWithStyle:(UITableViewCellStyle)style
    reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) { return nil; }

    self.backgroundColor      = kBgColor();
    self.selectionStyle       = UITableViewCellSelectionStyleNone;
    self.contentView.backgroundColor = kBgColor();

    /* ── Баббл (фон) ── */
    UIImageView *bubble = [[UIImageView alloc] initWithFrame:CGRectZero];
    bubble.contentMode  = UIViewContentModeScaleToFill;
    [self.contentView addSubview:bubble];
    self.bubbleView = bubble;
    [bubble release];

    /* ── Аватарка Gemini ── */
    UIImageView *avatar = [[UIImageView alloc] initWithFrame:CGRectZero];
    avatar.contentMode  = UIViewContentModeScaleAspectFit;
    avatar.hidden       = YES;

    /* Рисуем простую аватарку — G в кружке */
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(kAvatarSize, kAvatarSize), NO, 0.0f);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetRGBFillColor(ctx, 0.42f, 0.19f, 0.90f, 1.0f);
    CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, kAvatarSize, kAvatarSize));
    UIImage *avImg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    avatar.image       = avImg;
    avatar.layer.cornerRadius = kAvatarSize / 2.0f;
    avatar.clipsToBounds      = YES;

    [self.contentView addSubview:avatar];
    self.avatarView = avatar;
    [avatar release];

    /* ── Метка текста ── */
    UILabel *label   = [[UILabel alloc] initWithFrame:CGRectZero];
    label.font       = kMessageFont;
    label.textColor  = kBotTextColor();
    label.numberOfLines = 0;    /* перенос по словам */
    label.lineBreakMode = UILineBreakModeWordWrap;
    label.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:label];
    self.messageLabel = label;
    [label release];

    return self;
}

- (void)dealloc
{
    [_messageLabel release];
    [_bubbleView   release];
    [_avatarView   release];
    [super dealloc];
}

/* ── Публичный setter ── */
- (void)setMessage:(ChatMessage *)message
{
    _isUser = message.isUser;

    self.messageLabel.text      = message.text;
    self.messageLabel.textColor = message.isUser ? kUserTextColor() : kBotTextColor();

    /* Обновляем баббл */
    UIColor *bubbleColor = message.isUser ? kUserBubbleColor() : kBotBubbleColor();
    self.bubbleView.image = gemini_make_bubble_image(bubbleColor, 14.0f, 40.0f);

    /* Аватарка только у Gemini */
    self.avatarView.hidden = message.isUser;

    [self setNeedsLayout];
}

/* ── Layout ── */
- (void)layoutSubviews
{
    [super layoutSubviews];

    CGFloat W        = self.contentView.bounds.size.width;
    CGFloat maxBubW  = floorf(W * kBubbleMaxWidthFrac);
    CGFloat edgeMargin = kBubbleMarginEdge;

    /* Аватарка: только слева для Gemini */
    CGFloat avatarX = 0;
    if (!_isUser) {
        avatarX = edgeMargin;
        self.avatarView.frame = CGRectMake(avatarX, kBubblePadV,
                                           kAvatarSize, kAvatarSize);
        self.avatarView.hidden = NO;
    } else {
        self.avatarView.hidden = YES;
    }

    /* Ширина области под текст внутри баббла */
    CGFloat textMaxW = maxBubW - kBubblePadH * 2.0f;

    /* Высота текста: sizeWithFont:constrainedToSize:lineBreakMode: — iOS 2.0+ */
    CGSize textSize = [self.messageLabel.text
                       sizeWithFont:kMessageFont
                   constrainedToSize:CGSizeMake(textMaxW, 9999.0f)
                       lineBreakMode:UILineBreakModeWordWrap];

    CGFloat bubbleW = textSize.width  + kBubblePadH * 2.0f;
    CGFloat bubbleH = textSize.height + kBubblePadV * 2.0f;
    if (bubbleH < kBubbleMinHeight) { bubbleH = kBubbleMinHeight; }

    CGFloat bubbleX, textX;

    if (_isUser) {
        /* Пользователь — справа */
        bubbleX = W - edgeMargin - bubbleW;
        textX   = bubbleX + kBubblePadH;
    } else {
        /* Gemini — слева, после аватарки */
        CGFloat afterAvatar = edgeMargin + kAvatarSize + 6.0f;
        bubbleX = afterAvatar;
        textX   = bubbleX + kBubblePadH;
    }

    CGFloat bubbleY = kBubblePadV;
    self.bubbleView.frame = CGRectMake(bubbleX, bubbleY, bubbleW, bubbleH);

    /* Центрируем текст по вертикали внутри баббла */
    CGFloat textY = bubbleY + floorf((bubbleH - textSize.height) / 2.0f);
    self.messageLabel.frame = CGRectMake(textX, textY, textSize.width, textSize.height);
}

/* ── Статический расчёт высоты ── */
+ (CGFloat)cellHeightForMessage:(ChatMessage *)message
                    tableWidth:(CGFloat)tableWidth
{
    CGFloat maxBubW  = floorf(tableWidth * kBubbleMaxWidthFrac);
    CGFloat textMaxW = maxBubW - kBubblePadH * 2.0f;

    CGSize textSize = [message.text
                       sizeWithFont:kMessageFont
                   constrainedToSize:CGSizeMake(textMaxW, 9999.0f)
                       lineBreakMode:UILineBreakModeWordWrap];

    CGFloat bubbleH = textSize.height + kBubblePadV * 2.0f;
    if (bubbleH < kBubbleMinHeight) { bubbleH = kBubbleMinHeight; }

    return bubbleH + kBubblePadV * 2.0f;  /* + вертикальные отступы ячейки */
}

@end
