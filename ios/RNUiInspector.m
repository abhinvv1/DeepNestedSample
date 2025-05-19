//
//  RNUiInspector.m
//  RNInspectorKit
//
//  Created by Abhinav Pandey on 18/05/25.
//

#import "RNUiInspector.h"
#import <objc/runtime.h>

static const NSInteger MAX_TRAVERSAL_DEPTH = 70;
static const NSTimeInterval CACHE_DURATION_MS = 300;
NSString * const LOG_PREFIX = @"[RNUiInspectorKit] ";

static NSDictionary * _Nullable cachedUiTree = nil;
static NSTimeInterval lastTreeBuildTime = 0;
static NSInteger uiElementCounter = 0;

@implementation RNUiInspector

#pragma mark - UI Hierarchy Traversal and Property Extraction

+ (UIWindow *)getKeyWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        return window;
                    }
                }
                if (windowScene.windows.count > 0) {
                    return windowScene.windows.firstObject;
                }
            }
        }
    }

    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *keyWindow = UIApplication.sharedApplication.keyWindow;
    if (keyWindow) {
        return keyWindow;
    }
    if (UIApplication.sharedApplication.windows.count > 0) {
        return UIApplication.sharedApplication.windows.firstObject;
    }
    #pragma clang diagnostic pop
    
    NSLog(@"%@Could not find any window.", LOG_PREFIX);
    return nil;
}

+ (nullable UIView *)findRCTRootView:(UIView *)startView {
    if (!startView) return nil;
    Class rctRootViewClass = NSClassFromString(@"RCTRootView");
    if (!rctRootViewClass) {
        NSLog(@"%@RCTRootView class not found. Assuming non-React Native or hybrid context.", LOG_PREFIX);
        return nil;
    }

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:startView];
    NSMutableSet<NSValue *> *visited = [NSMutableSet set];

    while (queue.count > 0) {
        UIView *currentView = queue.firstObject;
        [queue removeObjectAtIndex:0];

        if (!currentView || [visited containsObject:[NSValue valueWithNonretainedObject:currentView]]) {
            continue;
        }
        [visited addObject:[NSValue valueWithNonretainedObject:currentView]];

        if ([currentView isKindOfClass:rctRootViewClass]) {
            NSLog(@"%@RCTRootView found: %@", LOG_PREFIX, currentView.description);
            return currentView;
        }
        for (UIView *subview in [currentView.subviews reverseObjectEnumerator]) {
            [queue addObject:subview];
        }
    }
    NSLog(@"%@RCTRootView not found starting from view: %@", LOG_PREFIX, startView.description);
    return nil;
}


+ (NSDictionary *)getPropertiesForView:(UIView *)view {
    if (!view) return @{};

    NSMutableDictionary *properties = [NSMutableDictionary dictionary];

    properties[@"type"] = NSStringFromClass(view.class);
    properties[@"testID"] = view.accessibilityIdentifier ?: [NSNull null];
    properties[@"accessibilityLabel"] = view.accessibilityLabel ?: [NSNull null];
    properties[@"accessibilityHint"] = view.accessibilityHint ?: [NSNull null];
    properties[@"accessibilityValue"] = view.accessibilityValue ?: [NSNull null];
    
    CGRect frameInWindow = [view.window convertRect:view.frame fromView:view.superview];
    if (view.window) {
         frameInWindow = [view convertRect:view.bounds toView:view.window];
    } else {
        frameInWindow = view.frame;
        NSLog(@"%@View %@ is not in a window. Frame coordinates may not be screen-relative.", LOG_PREFIX, view.accessibilityIdentifier ?: NSStringFromClass(view.class));
    }

    properties[@"frame"] = @{
        @"x": @(CGRectGetMinX(frameInWindow)),
        @"y": @(CGRectGetMinY(frameInWindow)),
        @"width": @(CGRectGetWidth(frameInWindow)),
        @"height": @(CGRectGetHeight(frameInWindow))
    };
    properties[@"center"] = @{
        @"x": @(CGRectGetMidX(frameInWindow)),
        @"y": @(CGRectGetMidY(frameInWindow))
    };
    
    properties[@"alpha"] = @(view.alpha);
    properties[@"hidden"] = @(view.isHidden);
    properties[@"userInteractionEnabled"] = @(view.isUserInteractionEnabled);
    properties[@"tag"] = @(view.tag);
    properties[@"opaque"] = @(view.isOpaque);
    
    BOOL isOnScreen = view.window && !view.isHidden && view.alpha > 0.01 && CGRectGetWidth(frameInWindow) > 0 && CGRectGetHeight(frameInWindow) > 0;
    if (isOnScreen && view.window) {
        CGRect screenBounds = view.window.screen.bounds;
        CGRect intersection = CGRectIntersection(frameInWindow, screenBounds);
        isOnScreen = !CGRectIsNull(intersection) && !CGRectIsEmpty(intersection);
    }
    properties[@"onScreen"] = @(isOnScreen);

    if ([view respondsToSelector:@selector(text)]) {
        NSString *text = ((UILabel *)view).text;
        properties[@"text"] = text ?: [NSNull null];
    }
    if ([view isKindOfClass:[UITextField class]]) {
        properties[@"placeholder"] = ((UITextField *)view).placeholder ?: [NSNull null];
    }

    if ([view isKindOfClass:[UIControl class]]) {
        UIControl *control = (UIControl *)view;
        properties[@"enabled"] = @(control.isEnabled);
        properties[@"selected"] = @(control.isSelected);
        properties[@"highlighted"] = @(control.isHighlighted);
    }

    if ([view isKindOfClass:[UISwitch class]]) {
        properties[@"value"] = @(((UISwitch *)view).isOn);
    } else if ([view isKindOfClass:[UISlider class]]) {
        properties[@"value"] = @(((UISlider *)view).value);
    } else if ([view isKindOfClass:[UIStepper class]]) {
        properties[@"value"] = @(((UIStepper *)view).value);
    } else if ([view isKindOfClass:[UISegmentedControl class]]) {
        properties[@"value"] = @(((UISegmentedControl *)view).selectedSegmentIndex);
        NSMutableArray *segmentTitles = [NSMutableArray array];
        for (NSUInteger i = 0; i < ((UISegmentedControl *)view).numberOfSegments; i++) {
            [segmentTitles addObject:[((UISegmentedControl *)view) titleForSegmentAtIndex:i] ?: @""];
        }
        properties[@"segmentTitles"] = segmentTitles;
    } else if ([view isKindOfClass:[UIImageView class]]) {
        properties[@"image"] = ((UIImageView *)view).image ? NSStringFromCGSize(((UIImageView *)view).image.size) : [NSNull null]; // Or a more descriptive string/flag
    }

    return [NSDictionary dictionaryWithDictionary:properties];
}

+ (nullable NSDictionary *)traverseViewRecursive:(UIView *)view
                                            path:(NSString *)path
                                           depth:(NSInteger)depth
                                 parentIsVisible:(BOOL)parentIsVisible {
    if (!view || depth > MAX_TRAVERSAL_DEPTH) {
        return nil;
    }
    uiElementCounter++;

    NSMutableDictionary *elementInfo = [[self getPropertiesForView:view] mutableCopy];
    elementInfo[@"nativeHandle"] = path;
    elementInfo[@"depth"] = @(depth);

    BOOL currentElementIsTechnicallyVisible = !view.isHidden && view.alpha > 0.01;
    BOOL effectivelyVisible = parentIsVisible && currentElementIsTechnicallyVisible;
    elementInfo[@"effectivelyVisible"] = @(effectivelyVisible);


    NSMutableArray *children = [NSMutableArray array];
    NSArray<UIView *> *subviews = view.subviews;
    for (NSUInteger i = 0; i < subviews.count; i++) {
        UIView *subview = subviews[i];
        NSString *childPath = [NSString stringWithFormat:@"%@/%@[%lu]", path, NSStringFromClass(subview.class), (unsigned long)i];
        NSDictionary *childElement = [self traverseViewRecursive:subview path:childPath depth:depth + 1 parentIsVisible:effectivelyVisible];
        if (childElement) {
            [children addObject:childElement];
        }
    }
    elementInfo[@"children"] = children;

    return [NSDictionary dictionaryWithDictionary:elementInfo];
}


+ (NSDictionary *)buildUiTreeForceRefresh:(BOOL)forceRefresh {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970] * 1000; // Current time in milliseconds
    if (!forceRefresh && cachedUiTree && (now - lastTreeBuildTime < CACHE_DURATION_MS)) {
        NSLog(@"%@Returning cached UI tree.", LOG_PREFIX);
        return cachedUiTree;
    }

    NSLog(@"%@Building UI tree (forceRefresh: %@)...", LOG_PREFIX, forceRefresh ? @"YES" : @"NO");
    uiElementCounter = 0;

    UIWindow *keyWindow = [self getKeyWindow];
    if (!keyWindow) {
        NSLog(@"%@Could not get key window. Aborting tree build.", LOG_PREFIX);
        cachedUiTree = nil;
        return nil;
    }

    UIView *rootViewControllerView = keyWindow.rootViewController.view;
    if (!rootViewControllerView) {
        NSLog(@"%@Could not get root view controller's view. Aborting tree build.", LOG_PREFIX);
        cachedUiTree = nil;
        return nil;
    }

    UIView *startView = [self findRCTRootView:rootViewControllerView] ?: rootViewControllerView;
    if (!startView) {
        NSLog(@"%@No valid start view found. Aborting tree build.", LOG_PREFIX);
        cachedUiTree = nil;
        return nil;
    }
    
    NSString *initialPath = [NSString stringWithFormat:@"/%@", NSStringFromClass(startView.class)];

    cachedUiTree = [self traverseViewRecursive:startView path:initialPath depth:0 parentIsVisible:YES];

    if (cachedUiTree) {
        lastTreeBuildTime = [[NSDate date] timeIntervalSince1970] * 1000;
        NSLog(@"%@UI tree built successfully. %ld elements processed. Root type: %@", LOG_PREFIX, (long)uiElementCounter, cachedUiTree[@"type"]);
    } else {
        NSLog(@"%@Failed to build UI tree.", LOG_PREFIX);
    }
    return cachedUiTree;
}

#pragma mark - Element Finding and Querying

+ (nullable UIView *)findViewByPath:(NSString *)path inRootView:(UIView *)rootView {
    if (!path || !rootView || [path isEqualToString:@"/"]) {
        if ([path isEqualToString:[NSString stringWithFormat:@"/%@", NSStringFromClass(rootView.class)]]) {
            return rootView;
        }
        return nil;
    }

    NSArray<NSString *> *components = [path componentsSeparatedByString:@"/"];
    UIView *currentView = rootView;

    for (NSUInteger i = 1; i < components.count; i++) {
        NSString *component = components[i];
        if (component.length == 0) continue;

        NSScanner *scanner = [NSScanner scannerWithString:component];
        NSString *className = nil;
        NSInteger index = 0;

        [scanner scanUpToString:@"[" intoString:&className];
        if (![scanner scanString:@"[" intoString:NULL] ||
            ![scanner scanInteger:&index] ||
            ![scanner scanString:@"]" intoString:NULL]) {
            NSLog(@"%@Invalid path component: %@", LOG_PREFIX, component);
            return nil;
        }

        if (!currentView || ![NSStringFromClass(currentView.class) isEqualToString:className]) {
             // This check is tricky if the first component of path is the root view itself.
             // The loop starts at i=1, so currentView should be the one matching components[i-1].
             // If i=1, className is from the first path segment. Check if currentView (rootView) matches.
            if (i == 1 && ![NSStringFromClass(currentView.class) isEqualToString:className]) {
                 NSLog(@"%@Root view class '%@' does not match path start '%@'", LOG_PREFIX, NSStringFromClass(currentView.class), className);
                 return nil;
            }
            // For subsequent components, currentView would have been set to a child in the previous iteration.
            // This path logic assumes the path always starts with the class name of the actual root traversal view.
        }
        
        if (index < 0 || index >= currentView.subviews.count) {
            NSLog(@"%@Index %ld out of bounds for subviews of %@ (count: %lu)", LOG_PREFIX, (long)index, NSStringFromClass(currentView.class), (unsigned long)currentView.subviews.count);
            return nil; // Index out of bounds
        }
        
        UIView *foundChild = nil;
        NSUInteger currentChildIndex = 0;
        // We need to find the child that matches both the class name and the index *within that class type* if the path implies that.
        // However, the current path generation `path/%@[%lu]` uses a simple subview index.
        // So, we directly use the index
        if (index < currentView.subviews.count) {
            UIView *potentialChild = currentView.subviews[index];
            if ([NSStringFromClass(potentialChild.class) isEqualToString:className]) { // This check is important
                currentView = potentialChild;
            } else {
                 NSLog(@"%@Subview at index %ld is of type '%@', expected '%@' from path component '%@'", LOG_PREFIX, (long)index, NSStringFromClass(potentialChild.class), className, component);
                 // Try to find the correct Nth child of that specific type if path implies that
                 // For now, strict path matching based on simple subview index and class.
                 NSUInteger matchingClassCounter = 0;
                 BOOL foundMatchingClassAndIndex = NO;
                 for(UIView *subview in currentView.subviews) {
                     if ([NSStringFromClass(subview.class) isEqualToString:className]) {
                         if (matchingClassCounter == index) {
                             currentView = subview;
                             foundMatchingClassAndIndex = YES;
                             break;
                         }
                         matchingClassCounter++;
                     }
                 }
                 if (!foundMatchingClassAndIndex) {
                    NSLog(@"%@Could not find child matching path component: %@", LOG_PREFIX, component);
                    return nil;
                 }
            }
        } else {
            NSLog(@"%@Index %ld out of bounds for path component %@", LOG_PREFIX, (long)index, component);
            return nil;
        }
    }
    return currentView;
}


+ (nullable NSDictionary *)findElementInNode:(NSDictionary *)node
                              withIdentifier:(NSString *)identifier
                                        type:(NSString *)identifierType {
    if (!node || !identifier || !identifierType) {
        return nil;
    }

    BOOL match = NO;
    id nodeValue = node[identifierType];

    if ([nodeValue isKindOfClass:[NSString class]] && [nodeValue isEqualToString:identifier]) {
        match = YES;
    } else if ([nodeValue respondsToSelector:@selector(isEqualToString:)] && [nodeValue isEqualToString:identifier]) { // For safety
        match = YES;
    }

    if (match) {
        NSMutableDictionary *foundElement = [node mutableCopy];
        [foundElement removeObjectForKey:@"children"]; // Return flat object
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

+ (NSArray<NSDictionary *> *)findElementsInNode:(NSDictionary *)node
                                 withCriteria:(NSDictionary<NSString *, id> *)criteria
                                      findAll:(BOOL)findAll {
    NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
    if (!node || !criteria || criteria.count == 0) {
        return results;
    }

    [self findElementsRecursive:node withCriteria:criteria results:results findAll:findAll];
    
    return results;
}

+ (void)findElementsRecursive:(NSDictionary *)currentNode
                 withCriteria:(NSDictionary<NSString *, id> *)criteria
                      results:(NSMutableArray<NSDictionary *> *)results
                    findAll:(BOOL)findAll {
    if (!findAll && results.count > 0) { // Optimization: if only first is needed and already found
        return;
    }

    BOOL matchesAllCriteria = YES;
    for (NSString *key in criteria) {
        id expectedValue = criteria[key];
        id actualValue = currentNode[key];

        if ([actualValue isEqual:[NSNull null]]) actualValue = nil;

        if (!actualValue && expectedValue) {
            matchesAllCriteria = NO;
            break;
        }
        if (actualValue && !expectedValue) {
            if (![expectedValue isEqual:[NSNull null]]) {
                 matchesAllCriteria = NO;
                 break;
            }
        }
        
        if (actualValue && expectedValue && ![expectedValue isEqual:[NSNull null]]) {
             if ([expectedValue isKindOfClass:[NSString class]] && [actualValue isKindOfClass:[NSString class]]) {
                if (![actualValue isEqualToString:expectedValue]) {
                    matchesAllCriteria = NO;
                    break;
                }
            } else if ([expectedValue isKindOfClass:[NSNumber class]] && [actualValue isKindOfClass:[NSNumber class]]) {
                if (![actualValue isEqualToNumber:expectedValue]) {
                    matchesAllCriteria = NO;
                    break;
                }
            } else if (![actualValue isEqual:expectedValue]) {
                matchesAllCriteria = NO;
                break;
            }
        }
    }

    if (matchesAllCriteria) {
        NSMutableDictionary *foundElement = [currentNode mutableCopy];
        [foundElement removeObjectForKey:@"children"];
        [results addObject:foundElement];
        if (!findAll) return;
    }

    NSArray *children = currentNode[@"children"];
    if ([children isKindOfClass:[NSArray class]]) {
        for (NSDictionary *childNode in children) {
            if ([childNode isKindOfClass:[NSDictionary class]]) {
                [self findElementsRecursive:childNode withCriteria:criteria results:results findAll:findAll];
                if (!findAll && results.count > 0) break;
            }
        }
    }
}


#pragma mark - Action Execution

+ (NSDictionary *)performNativeAction:(RNInspectorActionType)actionType
                        onElementPath:(NSString *)elementPath
                       withParameters:(nullable NSDictionary *)parameters {
    if (![NSThread isMainThread]) {
        __block NSDictionary *result;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [self performNativeActionOnMainThread:actionType onElementPath:elementPath withParameters:parameters];
        });
        return result;
    }
    return [self performNativeActionOnMainThread:actionType onElementPath:elementPath withParameters:parameters];
}

+ (NSDictionary *)performNativeActionOnMainThread:(RNInspectorActionType)actionType
                                    onElementPath:(NSString *)elementPath
                                   withParameters:(nullable NSDictionary *)parameters {
    NSLog(@"%@Attempting action %ld on path: %@", LOG_PREFIX, (long)actionType, elementPath);

    UIWindow *keyWindow = [self getKeyWindow];
    if (!keyWindow || !keyWindow.rootViewController.view) {
        return @{@"status": @"error", @"message": @"Could not get key window or root view."};
    }
    
    UIView *rctRootView = [self findRCTRootView:keyWindow.rootViewController.view] ?: keyWindow.rootViewController.view;
    if (!rctRootView) {
         return @{@"status": @"error", @"message": @"Could not find a suitable root view for path resolution."};
    }

    UIView *targetView = [self findViewByPath:elementPath inRootView:rctRootView];

    if (!targetView) {
        NSString *message = [NSString stringWithFormat:@"Element not found for path: %@", elementPath];
        NSLog(@"%@%@", LOG_PREFIX, message);
        return @{@"status": @"error", @"message": message};
    }

    BOOL isEffectivelyVisible = !targetView.isHidden && targetView.alpha > 0.01 && targetView.window;
    if (targetView.superview) {
        UIView *v = targetView.superview;
        while(v && v != targetView.window) {
            if (v.isHidden || v.alpha <= 0.01) {
                isEffectivelyVisible = NO;
                break;
            }
            v = v.superview;
        }
    }
    
    if (!isEffectivelyVisible) {
         NSString *message = [NSString stringWithFormat:@"Element at path %@ is not effectively visible for interaction.", elementPath];
         NSLog(@"%@%@", LOG_PREFIX, message);
         return @{@"status": @"error", @"message": message};
    }
    if (!targetView.isUserInteractionEnabled &&
        (actionType == RNInspectorActionTypeTap || actionType == RNInspectorActionTypeLongPress || actionType == RNInspectorActionTypeSetText)) {
        NSString *message = [NSString stringWithFormat:@"Element at path %@ has userInteractionEnabled=NO.", elementPath];
        NSLog(@"%@%@", LOG_PREFIX, message);
        return @{@"status": @"error", @"message": message};
    }
    if ([targetView isKindOfClass:[UIControl class]] && !((UIControl *)targetView).isEnabled &&
        (actionType == RNInspectorActionTypeTap || actionType == RNInspectorActionTypeLongPress || actionType == RNInspectorActionTypeSetText)) {
         NSString *message = [NSString stringWithFormat:@"Control at path %@ is not enabled.", elementPath];
         NSLog(@"%@%@", LOG_PREFIX, message);
         return @{@"status": @"error", @"message": message};
    }


    switch (actionType) {
        case RNInspectorActionTypeTap: {
            if ([targetView respondsToSelector:@selector(accessibilityActivate)]) {
                if ([targetView accessibilityActivate]) {
                     NSLog(@"%@Tap (accessibilityActivate) successful on: %@", LOG_PREFIX, elementPath);
                    return @{@"status": @"success", @"message": @"Tap performed via accessibilityActivate."};
                }
            }
            if ([targetView isKindOfClass:[UIControl class]]) {
                UIControl *control = (UIControl *)targetView;
                // Check if the control is enabled
                if (!control.isEnabled) {
                    return @{@"status": @"error", @"message": @"Control is not enabled."};
                }
                [control sendActionsForControlEvents:UIControlEventTouchUpInside];
                 NSLog(@"%@Tap (sendActionsForControlEvents) successful on: %@", LOG_PREFIX, elementPath);
                return @{@"status": @"success", @"message": @"Tap performed via sendActionsForControlEvents."};
            }
            NSLog(@"%@Tap action not fully supported for generic UIView type: %@. Tried accessibilityActivate.", LOG_PREFIX, NSStringFromClass(targetView.class));
            return @{@"status": @"error", @"message": @"Tap action not fully supported for this element type. Try making it a UIControl or ensure accessibilityActivate works."};
        }
            
        case RNInspectorActionTypeLongPress: {
            // Simulating a true long press programmatically without XCTest framework is tricky.
            // We can try to send touch events with delays, but this is not standard.
            // For UIControls, there isn't a standard "long press" event.
            // Often, long press is handled by UILongPressGestureRecognizer.
            // We could try to find and trigger such a recognizer if attached.
            
            // Simple approach: If it's a button, maybe just tap it as a fallback.
            // Or, if a gesture recognizer is found:
            for (UIGestureRecognizer *recognizer in targetView.gestureRecognizers) {
                if ([recognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
                    // This is tricky because setting state and calling handler is not public API.
                    // ((UILongPressGestureRecognizer *)recognizer).state = UIGestureRecognizerStateBegan;
                    // then UIGestureRecognizerStateEnded after a delay.
                    // This is highly unreliable and uses private-like behavior.
                    NSLog(@"%@Found UILongPressGestureRecognizer on %@. Programmatic triggering is complex/unreliable.", LOG_PREFIX, elementPath);
                    break;
                }
            }
            NSLog(@"%@Long press action is complex to simulate reliably without XCUITest. No standard programmatic trigger.", LOG_PREFIX);
            return @{@"status": @"error", @"message": @"Long press action not reliably implemented yet."};
        }

        case RNInspectorActionTypeSetText: {
            NSString *textToSet = parameters[@"text"];
            if (!textToSet || ![textToSet isKindOfClass:[NSString class]]) {
                return @{@"status": @"error", @"message": @"'text' parameter (string) is required for setText action."};
            }
            if ([targetView isKindOfClass:[UITextField class]]) {
                ((UITextField *)targetView).text = textToSet;
                [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:targetView];
                NSLog(@"%@SetText successful on UITextField: %@", LOG_PREFIX, elementPath);
                return @{@"status": @"success", @"message": @"Text set on UITextField."};
            } else if ([targetView isKindOfClass:[UITextView class]]) {
                ((UITextView *)targetView).text = textToSet;
                [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:targetView];
                 NSLog(@"%@SetText successful on UITextView: %@", LOG_PREFIX, elementPath);
                return @{@"status": @"success", @"message": @"Text set on UITextView."};
            } else if ([targetView respondsToSelector:@selector(setText:)]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [targetView performSelector:@selector(setText:) withObject:textToSet];
                #pragma clang diagnostic pop
                NSLog(@"%@SetText (generic setText:) attempted on: %@", LOG_PREFIX, elementPath);
                return @{@"status": @"success", @"message": @"Text set via generic setText: (may not trigger all updates)." };
            }
            NSLog(@"%@SetText action not supported for element type: %@", LOG_PREFIX, NSStringFromClass(targetView.class));
            return @{@"status": @"error", @"message": @"Element does not support setText action."};
        }
            
        case RNInspectorActionTypeClearText: {
             if ([targetView isKindOfClass:[UITextField class]]) {
                ((UITextField *)targetView).text = @"";
                [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:targetView];
                NSLog(@"%@ClearText successful on UITextField: %@", LOG_PREFIX, elementPath);
                return @{@"status": @"success", @"message": @"Text cleared on UITextField."};
            } else if ([targetView isKindOfClass:[UITextView class]]) {
                ((UITextView *)targetView).text = @"";
                [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:targetView];
                NSLog(@"%@ClearText successful on UITextView: %@", LOG_PREFIX, elementPath);
                return @{@"status": @"success", @"message": @"Text cleared on UITextView."};
            } else if ([targetView respondsToSelector:@selector(setText:)]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [targetView performSelector:@selector(setText:) withObject:@""];
                #pragma clang diagnostic pop
                NSLog(@"%@ClearText (generic setText:) attempted on: %@", LOG_PREFIX, elementPath);
                return @{@"status": @"success", @"message": @"Text cleared via generic setText: (may not trigger all updates)."};
            }
            NSLog(@"%@ClearText action not supported for element type: %@", LOG_PREFIX, NSStringFromClass(targetView.class));
            return @{@"status": @"error", @"message": @"Element does not support clearText action."};
        }
            
        case RNInspectorActionTypeScrollToVisible: {
            UIScrollView *scrollView = nil;
            UIView *viewToScroll = targetView;

            UIView *ancestor = targetView.superview;
            while (ancestor) {
                if ([ancestor isKindOfClass:[UIScrollView class]]) {
                    scrollView = (UIScrollView *)ancestor;
                    break;
                }
                ancestor = ancestor.superview;
            }

            if (scrollView) {
                CGRect targetFrameInScrollView = [scrollView convertRect:targetView.bounds fromView:targetView];
                CGRect visibleRectInScrollView = CGRectMake(scrollView.contentOffset.x, scrollView.contentOffset.y,
                                                            scrollView.bounds.size.width, scrollView.bounds.size.height);
                if (CGRectContainsRect(visibleRectInScrollView, targetFrameInScrollView)) {
                     NSLog(@"%@Element %@ already visible in scroll view.", LOG_PREFIX, elementPath);
                    return @{@"status": @"success", @"message": @"Element already visible in scroll view."};
                }

                [scrollView scrollRectToVisible:targetFrameInScrollView animated:YES];
                NSLog(@"%@ScrollToVisible attempted for: %@ within scrollview %@", LOG_PREFIX, elementPath, scrollView);
                return @{@"status": @"success", @"message": @"ScrollToVisible action initiated."};
            }
            NSLog(@"%@ScrollToVisible: No UIScrollView found as ancestor of %@", LOG_PREFIX, elementPath);
            return @{@"status": @"error", @"message": @"No scroll view found to perform scroll."};
        }

        default:
             NSLog(@"%@Unknown action type: %ld", LOG_PREFIX, (long)actionType);
            return @{@"status": @"error", @"message": @"Unknown action type."};
    }
}


#pragma mark - Element Metadata Retrieval

+ (nullable NSDictionary *)getElementMetadataByPath:(NSString *)elementPath {
    if (![NSThread isMainThread]) {
        __block NSDictionary *result;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [self getElementMetadataByPathOnMainThread:elementPath];
        });
        return result;
    }
    return [self getElementMetadataByPathOnMainThread:elementPath];
}

+ (nullable NSDictionary *)getElementMetadataByPathOnMainThread:(NSString *)elementPath {
    NSLog(@"%@Getting metadata for path: %@", LOG_PREFIX, elementPath);
    UIWindow *keyWindow = [self getKeyWindow];
    if (!keyWindow || !keyWindow.rootViewController.view) {
        NSLog(@"%@GetMetadata: Could not get key window or root view.", LOG_PREFIX);
        return nil;
    }
    
    UIView *rctRootView = [self findRCTRootView:keyWindow.rootViewController.view] ?: keyWindow.rootViewController.view;
     if (!rctRootView) {
        NSLog(@"%@GetMetadata: Could not find a suitable root view for path resolution.", LOG_PREFIX);
        return nil;
    }

    UIView *targetView = [self findViewByPath:elementPath inRootView:rctRootView];

    if (!targetView) {
        NSLog(@"%@GetMetadata: Element not found for path: %@", LOG_PREFIX, elementPath);
        return nil;
    }

    NSDictionary *properties = [self getPropertiesForView:targetView];
    NSMutableDictionary *elementInfo = [properties mutableCopy];
    elementInfo[@"nativeHandle"] = elementPath;
    elementInfo[@"depth"] = @(-1);
    
    NSLog(@"%@GetMetadata: Successfully retrieved metadata for %@", LOG_PREFIX, elementPath);
    return [NSDictionary dictionaryWithDictionary:elementInfo];
}


@end
