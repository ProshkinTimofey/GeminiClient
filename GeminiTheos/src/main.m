/*
 * main.m — GeminiClient (Theos, MRC, iOS 3.0+)
 *
 * iOS 3.0 совместимость:
 *   - Нет @autoreleasepool {} (доступен с iOS 5+ / LLVM 3+)
 *   - Используем NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
 *   - UIApplicationMain принимает argc/argv — стандарт с iOS 2.0.
 */

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int retVal = UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    [pool release];
    return retVal;
}
