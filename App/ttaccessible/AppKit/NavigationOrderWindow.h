//
//  NavigationOrderWindow.h
//  ttaccessible
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// An NSWindow whose navigation order (AXChildrenInNavigationOrder) a Swift subclass can
/// rewrite. The override has to live in Objective-C: AppKit's list holds elements that do
/// not conform to NSAccessibilityElementProtocol, and Swift's typed override force-casts
/// the array on the way in and out, which traps.
@interface NavigationOrderWindow : NSWindow

/// Given the order AppKit computed, return the one to hand VoiceOver. Returns `order` as is.
- (NSArray *)navigationOrderFromAppKitOrder:(NSArray *)order;

@end

NS_ASSUME_NONNULL_END
