#import <AppKit/AppKit.h>

// Touch Bar SPI. These have existed since 10.12 and are still present on
// macOS 26 (verified with -[NSObject respondsToSelector:] at runtime before
// anything here is called). Declaring them in a category is enough — ObjC
// method dispatch needs no link-time symbol.

@interface NSTouchBarItem (TBToysPrivate)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (TBToysPrivate)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
                         placement:(long long)placement
          systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)touchBar;
@end
