//
//  RNUiInspector.m
//  RNInspectorKit
//
//  Created by Abhinav Pandey on 18/05/25.
//


#import "RNUiInspector.h"

// Configuration
static const NSInteger MAX_TRAVERSAL_DEPTH = 70;
static const NSTimeInterval CACHE_DURATION_MS = 500; // Milliseconds

// Globals for caching
static NSDictionary * _Nullable cachedUiTree = nil;
static NSTimeInterval lastTreeBuildTime = 0;
static NSInteger uiElementCounter = 0;

@implementation RNUiInspector

+ (UIWindow *)getKeyWindow {
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }
            }
            if (keyWindow) break;
        }
    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = UIApplication.sharedApplication.keyWindow;
        #pragma clang diagnostic pop
    }
    
    // Fallback if no key window found yet (e.g. app just launched)
    if (!keyWindow) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSArray *windows = UIApplication.sharedApplication.windows;
        #pragma clang diagnostic pop
        for (UIWindow *window in windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        // If still no key window, take the first one that is a UIWindow
        if (!keyWindow && windows.count > 0 && [windows.firstObject isKindOfClass:[UIWindow class]]) {
            keyWindow = windows.firstObject;
        }
    }
    return keyWindow;
}

+ (nullable UIView *)findRCTRootView:(UIView *)startView {
    if (!startView) return nil;
    Class rctRootViewClass = NSClassFromString(@"RCTRootView");
    if (!rctRootViewClass) {
        NSLog(@"[RNUiInspector] RCTRootView class not found. Is this a React Native app?");
        return nil; // Or handle as pure native if desired
    }

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:startView];
    NSMutableSet<NSValue *> *visited = [NSMutableSet set]; // To avoid cycles with view pointers

    while (queue.count > 0) {
        UIView *currentView = queue.firstObject;
        [queue removeObjectAtIndex:0];

        if (!currentView || [visited containsObject:[NSValue valueWithNonretainedObject:currentView]]) {
            continue;
        }
        [visited addObject:[NSValue valueWithNonretainedObject:currentView]];

        if ([currentView isKindOfClass:rctRootViewClass]) {
            NSLog(@"[RNUiInspector] RCTRootView found: %@", currentView);
            return currentView;
        }

        for (UIView *subview in currentView.subviews) {
            [queue addObject:subview];
        }
    }
    NSLog(@"[RNUiInspector] RCTRootView not found starting from view: %@", startView);
    return nil;
}

+ (NSDictionary *)getScreenCoordinatesForView:(UIView *)view {
    if (!view) return @{};
    
    BOOL onScreen = NO;
    CGRect rectInWindow = CGRectZero;

    if (view.window) {
        // Convert view's bounds to the window's coordinate system (effectively screen coordinates for non-transformed windows)
        rectInWindow = [view convertRect:view.bounds toView:nil];
        onScreen = YES;
    } else {
        // View is not in a window, coordinates are local to its superview (if any) or just its frame.
        // This might not be truly "screen" coordinates.
        rectInWindow = view.frame;
        onScreen = NO;
        NSLog(@"[RNUiInspector] View %@ is not in a window. Coordinates might not be screen-relative.", view.accessibilityIdentifier ?: NSStringFromClass(view.class));
    }

    return @{
        @"x": @(rectInWindow.origin.x),
        @"y": @(rectInWindow.origin.y),
        @"width": @(rectInWindow.size.width),
        @"height": @(rectInWindow.size.height),
        @"centerX": @(CGRectGetMidX(rectInWindow)),
        @"centerY": @(CGRectGetMidY(rectInWindow)),
        @"onScreen": @(onScreen)
    };
}

+ (nullable NSDictionary *)traverseViewRecursive:(UIView *)view
                                            path:(NSString *)path
                                           depth:(NSInteger)depth {
    if (!view || depth > MAX_TRAVERSAL_DEPTH) {
        return nil;
    }
    uiElementCounter++;

    NSString *testID = view.accessibilityIdentifier;
    NSString *accessibilityLabel = view.accessibilityLabel;
    NSString *className = NSStringFromClass(view.class);
    NSDictionary *frameInfo = [self getScreenCoordinatesForView:view];
    NSString *nativeTag = view.tag != 0 ? [NSString stringWithFormat:@"%ld", (long)view.tag] : nil;

    NSMutableArray *children = [NSMutableArray array];
    NSArray<UIView *> *subviews = view.subviews;
    for (NSUInteger i = 0; i < subviews.count; i++) {
        UIView *subview = subviews[i];
        NSString *childPath = [NSString stringWithFormat:@"%@/%@[%lu]", path, NSStringFromClass(subview.class), (unsigned long)i];
        NSDictionary *childElement = [self traverseViewRecursive:subview path:childPath depth:depth + 1];
        if (childElement) {
            [children addObject:childElement];
        }
    }
    
    NSMutableDictionary *elementInfo = [NSMutableDictionary dictionary];
    elementInfo[@"type"] = className ?: [NSNull null];
    elementInfo[@"testID"] = testID ?: [NSNull null]; // Use NSNull for nil values for JSON serialization
    elementInfo[@"accessibilityLabel"] = accessibilityLabel ?: [NSNull null];
    elementInfo[@"tag"] = nativeTag ?: [NSNull null];
    elementInfo[@"frame"] = frameInfo[@"onScreen"] && frameInfo[@"x"] ? @{
        @"x": frameInfo[@"x"], @"y": frameInfo[@"y"],
        @"width": frameInfo[@"width"], @"height": frameInfo[@"height"]
    } : [NSNull null];
    elementInfo[@"center"] = frameInfo[@"onScreen"] && frameInfo[@"centerX"] ? @{
        @"x": frameInfo[@"centerX"], @"y": frameInfo[@"centerY"]
    } : [NSNull null];
    elementInfo[@"nativeHandle"] = path ?: [NSNull null];
    elementInfo[@"onScreen"] = frameInfo[@"onScreen"] ?: @(NO);
    elementInfo[@"children"] = children;

    return [NSDictionary dictionaryWithDictionary:elementInfo];
}

+ (NSDictionary *)buildUiTreeForceRefresh:(BOOL)forceRefresh {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970] * 1000;
    if (!forceRefresh && cachedUiTree && (now - lastTreeBuildTime < CACHE_DURATION_MS)) {
        NSLog(@"[RNUiInspector] Returning cached UI tree.");
        return cachedUiTree;
    }

    NSLog(@"[RNUiInspector] Building UI tree...");
    uiElementCounter = 0;
    UIWindow *keyWindow = [self getKeyWindow];
    if (!keyWindow) {
        NSLog(@"[RNUiInspector] Could not get key window.");
        cachedUiTree = nil;
        return nil;
    }

    UIView *rootViewControllerView = keyWindow.rootViewController.view;
    if (!rootViewControllerView) {
        NSLog(@"[RNUiInspector] Could not get root view controller's view.");
        cachedUiTree = nil;
        return nil;
    }

    UIView *startView = [self findRCTRootView:rootViewControllerView];
    if (!startView) {
        NSLog(@"[RNUiInspector] RCTRootView not found, falling back to rootViewControllerView.");
        startView = rootViewControllerView; // Fallback for non-RN or hybrid parts
    }
    
    if (!startView) {
        NSLog(@"[RNUiInspector] No valid start view found for traversal.");
        cachedUiTree = nil;
        return nil;
    }

    cachedUiTree = [self traverseViewRecursive:startView
                                          path:[NSString stringWithFormat:@"/%@", NSStringFromClass(startView.class)]
                                         depth:0];

    if (cachedUiTree) {
        NSLog(@"[RNUiInspector] UI tree built. %ld elements processed. Root type: %@", (long)uiElementCounter, cachedUiTree[@"type"]);
        lastTreeBuildTime = now;
    } else {
        NSLog(@"[RNUiInspector] Failed to build UI tree.");
    }
    return cachedUiTree;
}

+ (nullable NSDictionary *)findElementInNode:(NSDictionary *)node
                          withIdentifier:(NSString *)identifier
                                    type:(NSString *)identifierType {
    if (!node || !identifier || !identifierType) {
        return nil;
    }

    BOOL match = NO;
    if ([identifierType isEqualToString:@"testID"] && [node[@"testID"] isKindOfClass:[NSString class]] && [node[@"testID"] isEqualToString:identifier]) {
        match = YES;
    } else if ([identifierType isEqualToString:@"accessibilityLabel"] && [node[@"accessibilityLabel"] isKindOfClass:[NSString class]] && [node[@"accessibilityLabel"] isEqualToString:identifier]) {
        match = YES;
    } else if ([identifierType isEqualToString:@"nativeHandle"] && [node[@"nativeHandle"] isKindOfClass:[NSString class]] && [node[@"nativeHandle"] isEqualToString:identifier]) {
        match = YES;
    }

    if (match) {
        // Return a flat object without children
        NSMutableDictionary *foundElement = [node mutableCopy];
        [foundElement removeObjectForKey:@"children"];
        return foundElement;
    }

    NSArray *children = node[@"children"];
    if ([children isKindOfClass:[NSArray class]]) {
        for (NSDictionary *childNode in children) {
            if ([childNode isKindOfClass:[NSDictionary class]]) {
                NSDictionary *found = [self findElementInNode:childNode withIdentifier:identifier type:identifierType];
                if (found) {
                    return found;
                }
            }
        }
    }
    return nil;
}

@end
