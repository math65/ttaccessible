//
//  NavigationOrderWindow.m
//  ttaccessible
//

#import "NavigationOrderWindow.h"

@implementation NavigationOrderWindow

- (nullable NSArray *)accessibilityChildrenInNavigationOrder {
    NSArray *order = [super accessibilityChildrenInNavigationOrder];
    return order ? [self navigationOrderFromAppKitOrder:order] : nil;
}

- (NSArray *)navigationOrderFromAppKitOrder:(NSArray *)order {
    return order;
}

@end
