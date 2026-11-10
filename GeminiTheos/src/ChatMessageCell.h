/*
 * ChatMessageCell.h — GeminiClient (Theos, MRC, iOS 3.0+)
 *
 * Кастомная ячейка чата. Баббл слева (Gemini) / справа (User).
 * Layout — строго через layoutSubviews + CGRect.
 * Высота — через sizeWithFont:constrainedToSize:lineBreakMode:
 */

#import <UIKit/UIKit.h>

/* Пороги геометрии баббла */
#define kBubblePadH         12.0f   /* горизонтальный внутренний отступ */
#define kBubblePadV          8.0f   /* вертикальный внутренний отступ    */
#define kBubbleMarginEdge   12.0f   /* отступ от края экрана             */
#define kBubbleMaxWidthFrac  0.72f  /* макс. ширина баббла = 72% экрана  */
#define kBubbleMinHeight    36.0f   /* минимальная высота баббла         */
#define kAvatarSize         32.0f   /* диаметр аватарки Gemini           */

/* Шрифт сообщения (единый источник истины — используется и в heightForRow) */
#define kMessageFont        [UIFont systemFontOfSize:14.0f]

/* ═══════════════════════════════════════════════════════════════════════════
 * ChatMessage — простая модель одного сообщения (MRC)
 * ═══════════════════════════════════════════════════════════════════════════ */
@interface ChatMessage : NSObject
{
    NSString *_text;
    BOOL      _isUser;
    NSDate   *_timestamp;
}

@property (nonatomic, copy)   NSString *text;
@property (nonatomic, assign) BOOL      isUser;
@property (nonatomic, retain) NSDate   *timestamp;

+ (ChatMessage *)messageWithText:(NSString *)text isUser:(BOOL)isUser;

@end

/* ═══════════════════════════════════════════════════════════════════════════
 * ChatMessageCell
 * ═══════════════════════════════════════════════════════════════════════════ */
@interface ChatMessageCell : UITableViewCell
{
    UILabel     *_messageLabel;   /* текст сообщения                    */
    UIImageView *_bubbleView;     /* фон баббла (stretchable)           */
    UIImageView *_avatarView;     /* аватарка Gemini (только isUser=NO) */

    BOOL         _isUser;         /* YES = пользователь, NO = Gemini    */
}

@property (nonatomic, retain) UILabel     *messageLabel;
@property (nonatomic, retain) UIImageView *bubbleView;
@property (nonatomic, retain) UIImageView *avatarView;
@property (nonatomic, assign) BOOL         isUser;

/* Задаёт текст и флаг — вызывает setNeedsLayout */
- (void)setMessage:(ChatMessage *)message;

/*
 * Статический метод расчёта высоты ячейки.
 * Вызывается из tableView:heightForRowAtIndexPath: (не cacheируется здесь —
 * UITableView уже держит кэш в layoutManager).
 */
+ (CGFloat)cellHeightForMessage:(ChatMessage *)message
                    tableWidth:(CGFloat)tableWidth;

@end
