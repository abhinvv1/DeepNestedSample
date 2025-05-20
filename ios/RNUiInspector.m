//
//  RNUiInspector.m
//  RNInspectorKit
//
//  Created by Abhinav Pandey on 18/05/25.
//

#import "RNUiInspector.h"
#import <objc/runtime.h>

static const NSInteger DEFAULT_MAX_TRAVERSAL_DEPTH = 100; // This is an abs depth limit for the UI tree traversal. The xcui limit is 60.
static const NSTimeInterval DEFAULT_CACHE_DURATION_MS = 300;
NSString * const LOG_PREFIX = @"[RNUiInspectorKit] ";
NSString * const kRNUiInspectorNativeHandleKey = @"nativeHandle"; // Key for the element's unique path.


static NSDictionary * _Nullable cachedUiTree = nil;
static NSTimeInterval lastTreeBuildTimeMs = 0;
static NSInteger uiElementCounterForLastBuild = 0;

@implementation RNUiInspector

#pragma mark - Configuration Accessors (Optional)

+ (NSInteger)maxTraversalDepth {
    // TODO: Make this configurable
    return DEFAULT_MAX_TRAVERSAL_DEPTH;
}

+ (NSTimeInterval)cacheDurationMs {
    // TODO: Make this configurable
    return DEFAULT_CACHE_DURATION_MS;
}

#pragma mark - UI Hierarchy Traversal & Property Extraction

/**
 * @brief Gets the key window of the application.
 * Learn more about key window here: https://reactnative.dev/docs/roottag
 * @return The key UIWindow object or nil if not found.
 */
+ (nullable UIWindow *)getKeyWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        return window;
                    }
                }
                // Fallback to the first active window if no explicit key window.
                if (windowScene.windows.count > 0) {
                    // Often, the first window is the main one if isKeyWindow isn't set on any.
                    return windowScene.windows.firstObject;
                }
            }
        }
    }

    // Fallback for older iOS versions or if scenes API doesn't yield a window.
    // Suggested by the ChatGPT.
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *keyWindow = UIApplication.sharedApplication.keyWindow;
    if (keyWindow) {
        return keyWindow;
    }
    // If keyWindow is nil, try the first window in the windows array.
    if (UIApplication.sharedApplication.windows.count > 0) {
        return UIApplication.sharedApplication.windows.firstObject;
    }
    #pragma clang diagnostic pop
    
    NSLog(@"%@Could not find any suitable window.", LOG_PREFIX);
    return nil;
}

/**
 * @brief Finds the RCTRootView starting from a given view.
 * This helps target the React Native specific part of the hierarchy if present.
 * @param startView The UIView to begin the search from.
 * @return The found RCTRootView, or nil if not found.
 */
+ (nullable UIView *)findRCTRootView:(UIView *)startView {
    if (!startView) return nil;
    Class rctRootViewClass = NSClassFromString(@"RCTRootView");
    if (!rctRootViewClass) {
        // This is not an error, just means it's not a standard RN app or RN part isn't loaded.
        // NSLog(@"%@RCTRootView class not found. Proceeding with standard UIKit traversal.", LOG_PREFIX);
        return nil;
    }

    // Breadth-first search for RCTRootView
    // Using a queue to traverse the view hierarchy.
    // This is a simple BFS implementation to find the first RCTRootView.
    // Using NSMutableArray for queue and NSMutableSet for visited nodes to avoid cycles.
    // Note: UIView hierarchy is typically acyclic, but this is a safe practice.
    NSLog(@"%@Starting search for RCTRootView from: %@", LOG_PREFIX, startView.description);
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
        // Add subviews to the queue for further searching (typically in reverse for intuitive order if needed, but BFS order is fine here).
        for (UIView *subview in currentView.subviews) {
            [queue addObject:subview];
        }
    }
    NSLog(@"%@RCTRootView not found starting from view: %@", LOG_PREFIX, startView.description);
    return nil;
}

/**
 * @brief Extracts properties from a given UIView.
 * This is the core method for gathering element metadata.
 * @param view The UIView to extract properties from.
 * @return A dictionary of properties.
 */
+ (NSDictionary<NSString *, id> *)getPropertiesForView:(UIView *)view {
    if (!view) return @{};

    NSMutableDictionary<NSString *, id> *properties = [NSMutableDictionary dictionary];

    properties[@"type"] = NSStringFromClass(view.class);
    properties[@"testID"] = view.accessibilityIdentifier ?: [NSNull null];
    properties[@"accessibilityLabel"] = view.accessibilityLabel ?: [NSNull null];
    properties[@"accessibilityHint"] = view.accessibilityHint ?: [NSNull null];
    properties[@"accessibilityValue"] = view.accessibilityValue ?: [NSNull null];
    properties[@"accessibilityTraits"] = @(view.accessibilityTraits);

    // Frame and Center Coordinates (imp: relative to the screen/window)
    CGRect frameInWindow;
    CGPoint centerInWindow;

    if (view.window) {
        // Converts the view's bounds to the coordinate system of its window.
        // This provides coordinates relative to the window, which are generally what's needed for interactions.
        frameInWindow = [view convertRect:view.bounds toView:view.window];
    } else {
        // If the view is not in a window, it's likely not visible or interactable in the standard sense.
        // Its 'frame' property is relative to its superview.
        frameInWindow = view.frame; // Fallback to frame relative to superview. Suggested by ChatGPT.
        NSLog(@"%@View '%@' (type: %@) is not in a window. 'frame' coordinates are relative to its superview and may not be screen-relative for interaction.",
              LOG_PREFIX,
              view.accessibilityIdentifier ?: @"<no-id>",
              NSStringFromClass(view.class));
    }
    properties[@"frame"] = @{
        @"x": @(CGRectGetMinX(frameInWindow)),
        @"y": @(CGRectGetMinY(frameInWindow)),
        @"width": @(CGRectGetWidth(frameInWindow)),
        @"height": @(CGRectGetHeight(frameInWindow))
    };
    centerInWindow = CGPointMake(CGRectGetMidX(frameInWindow), CGRectGetMidY(frameInWindow));
    properties[@"center"] = @{@"x": @(centerInWindow.x), @"y": @(centerInWindow.y)};

    properties[@"alpha"] = @(view.alpha);
    properties[@"hidden"] = @(view.isHidden); // Equivalent to UIAccessibilityElement.accessibilityFrame == CGRectZero
    properties[@"userInteractionEnabled"] = @(view.isUserInteractionEnabled);
    properties[@"opaque"] = @(view.isOpaque);
    
    BOOL isEffectivelyVisible = view.window && !view.isHidden && view.alpha > 0.01 && CGRectGetWidth(frameInWindow) > 0 && CGRectGetHeight(frameInWindow);
    if (isEffectivelyVisible) {
        // Further check if it's within screen bounds (though WDA might handle off-screen taps already)
        CGRect screenBounds = view.window.screen.bounds;
        CGRect intersection = CGRectIntersection(frameInWindow, screenBounds);
        isEffectivelyVisible = !CGRectIsNull(intersection) && !CGRectIsEmpty(intersection);
        
        UIView *v = view.superview;
        while(v && v != view.window) { // Traverse up to the window
            if (v.isHidden || v.alpha <= 0.01) {
                isEffectivelyVisible = NO;
                break;
            }
            v = v.superview;
        }
    }
    properties[@"isEffectivelyVisible"] = @(isEffectivelyVisible);
    properties[@"tag"] = @(view.tag);

    if ([view respondsToSelector:@selector(text)]) {
        NSString *text = ((UILabel *)view).text; // Common for UILabel, UITextField, UITextView (though UITextView has its own)
        properties[@"text"] = text ?: [NSNull null];
    }
    if ([view isKindOfClass:[UITextView class]]) { // Explicitly for UITextView if 'text' property isn't caught above or is different
        properties[@"text"] = ((UITextView *)view).text ?: [NSNull null];
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
        UISegmentedControl *segmentedControl = (UISegmentedControl *)view;
        properties[@"value"] = @(segmentedControl.selectedSegmentIndex);
        NSMutableArray *segmentTitles = [NSMutableArray array];
        for (NSUInteger i = 0; i < segmentedControl.numberOfSegments; i++) {
            [segmentTitles addObject:[segmentedControl titleForSegmentAtIndex:i] ?: @""];
        }
        properties[@"segmentTitles"] = segmentTitles;
    } else if ([view isKindOfClass:[UIImageView class]]) {
        UIImage *image = ((UIImageView *)view).image;
        properties[@"image"] = image ? [NSString stringWithFormat:@"UIImage (%fx%f)", image.size.width, image.size.height] : [NSNull null];
    }
    
    // Add more properties as needed for Appium compatibility, e.g., focused state
    // We can add more properties here as needed for Appium compatibility.
    properties[@"isFocused"] = @(view.isFirstResponder);

    return [NSDictionary dictionaryWithDictionary:properties];
}

/**
 * @brief Recursively traverses the UIView hierarchy to build a dictionary representation.
 * @param view The current UIView to process.
 * @param path The nativeHandle path string built so far for this view.
 * @param depth The current depth in the traversal.
 * @param parentIsEffectivelyVisible Effective visibility of the parent view.
 * @return A dictionary representing the element and its children, or nil if max depth exceeded or view is nil.
 */
+ (nullable NSDictionary *)traverseViewRecursive:(UIView *)view
                                            path:(NSString *)path
                                           depth:(NSInteger)depth
                      parentIsEffectivelyVisible:(BOOL)parentIsEffectivelyVisible {
    if (!view || depth > [self maxTraversalDepth]) {
        if (depth > [self maxTraversalDepth]) {
            NSLog(@"%@Max traversal depth (%ld) reached at view: %@, path: %@", LOG_PREFIX, (long)[self maxTraversalDepth], view.accessibilityIdentifier ?: NSStringFromClass(view.class), path);
        }
        return nil;
    }
    uiElementCounterForLastBuild++;

    NSMutableDictionary *elementInfo = [[self getPropertiesForView:view] mutableCopy];
    elementInfo[kRNUiInspectorNativeHandleKey] = path;
    elementInfo[@"depth"] = @(depth);

    BOOL currentViewIsTechnicallyVisible = ![elementInfo[@"hidden"] boolValue] && [elementInfo[@"alpha"] floatValue] > 0.01;
    BOOL isCurrentlyEffectivelyVisible = parentIsEffectivelyVisible && currentViewIsTechnicallyVisible;
    elementInfo[@"isEffectivelyVisible"] = @(isCurrentlyEffectivelyVisible);

    NSMutableArray<NSDictionary *> *children = [NSMutableArray array];
    // Iterate over subviews in their natural order (important for path indexing)
    NSArray<UIView *> *subviews = view.subviews;
    for (NSUInteger i = 0; i < subviews.count; i++) {
        UIView *subview = subviews[i];
        // Construct child path: /ParentType[idx]/CurrentType[subviewIndex]
        // Note: We use NSStringFromClass to get the class name for the path.
        NSString *childPath = [NSString stringWithFormat:@"%@/%@[%lu]", path, NSStringFromClass(subview.class), (unsigned long)i];
        NSDictionary *childElement = [self traverseViewRecursive:subview
                                                            path:childPath
                                                           depth:depth + 1
                                      parentIsEffectivelyVisible:isCurrentlyEffectivelyVisible];
        if (childElement) {
            [children addObject:childElement];
        }
    }
    elementInfo[@"children"] = children;

    return [NSDictionary dictionaryWithDictionary:elementInfo];
}

#pragma mark - Public API: UI Tree Building

+ (nullable NSDictionary *)buildUiTreeForceRefresh:(BOOL)forceRefresh {
    NSTimeInterval currentTimeMs = [[NSDate date] timeIntervalSince1970] * 1000;
    if (!forceRefresh && cachedUiTree && (currentTimeMs - lastTreeBuildTimeMs < [self cacheDurationMs])) {
        NSLog(@"%@Returning cached UI tree (built %.0fms ago).", LOG_PREFIX, currentTimeMs - lastTreeBuildTimeMs);
        return cachedUiTree;
    }

    NSLog(@"%@Building UI tree (forceRefresh: %@)...", LOG_PREFIX, forceRefresh ? @"YES" : @"NO");
    uiElementCounterForLastBuild = 0;

    UIWindow *keyWindow = [self getKeyWindow];
    if (!keyWindow) {
        NSLog(@"%@Could not get key window. Aborting tree build.", LOG_PREFIX);
        cachedUiTree = nil; // Invalidate cache on failure, a very important learning from the WDA code.
        return nil;
    }

    UIView *rootViewControllerView = keyWindow.rootViewController.view;
    if (!rootViewControllerView) {
        NSLog(@"%@Could not get root view controller's view. Aborting tree build.", LOG_PREFIX);
        cachedUiTree = nil; // Invalidate cache on failure, a very important learning from the WDA code.
        return nil;
    }

    UIView *startView = [self findRCTRootView:rootViewControllerView] ?: rootViewControllerView;
    if (!startView) { // Should not happen if rootViewControllerView is valid
        NSLog(@"%@No valid start view found (should be rootViewControllerView at least). Aborting tree build.", LOG_PREFIX);
        cachedUiTree = nil; // Invalidate cache on failure, a very important learning from the WDA code.
        return nil;
    }

    // The initial path starts with the class name of the actual startView and index 0 (as it's the root of traversal).
    NSString *initialPath = [NSString stringWithFormat:@"/%@[0]", NSStringFromClass(startView.class)];

    // Start traversal. The root is considered effectively visible initially.
    NSDictionary *tree = [self traverseViewRecursive:startView path:initialPath depth:0 parentIsEffectivelyVisible:YES];

    if (tree) {
        cachedUiTree = tree;
        lastTreeBuildTimeMs = [[NSDate date] timeIntervalSince1970] * 1000;
        NSLog(@"%@UI tree built successfully. %ld elements processed. Root type: %@", LOG_PREFIX, (long)uiElementCounterForLastBuild, cachedUiTree[@"type"]);
    } else {
        cachedUiTree = nil; // Invalidate cache on failure, a very important learning from the WDA code.
        NSLog(@"%@Failed to build UI tree.", LOG_PREFIX);
    }
    return cachedUiTree;
}

#pragma mark - Native UIView Finding (from Path)

/**
 * @brief Finds a UIView in the live hierarchy using its nativeHandle (path).
 * This is crucial for getElementMetadataByNativeHandle.
 * @param path The nativeHandle path of the view to find.
 * @param rootView The UIView to start searching from (usually the main RCTRootView or window's root view).
 * @return The found UIView, or nil if not found or path is invalid.
 */
+ (nullable UIView *)findViewByPath:(NSString *)path inRootView:(UIView *)rootView {
    if (!path || path.length == 0 || !rootView) {
        return nil;
    }

    // Path example: "/RCTRootView[0]/RCTView[1]/CustomText[0]"
    NSArray<NSString *> *components = [path componentsSeparatedByString:@"/"];
    UIView *currentView = rootView;

    // Start from component at index 1 (index 0 is empty due to leading "/")
    for (NSUInteger i = 1; i < components.count; i++) {
        NSString *component = components[i];
        if (component.length == 0) continue; // Should not happen with valid paths

        NSScanner *scanner = [NSScanner scannerWithString:component];
        NSString *expectedClassName = nil;
        NSInteger expectedIndex = -1;

        [scanner scanUpToString:@"[" intoString:&expectedClassName];
        if (![scanner scanString:@"[" intoString:NULL] ||
            ![scanner scanInteger:&expectedIndex] ||
            ![scanner scanString:@"]" intoString:NULL] ||
            expectedIndex < 0) {
            NSLog(@"%@Invalid path component format: '%@' in path '%@'", LOG_PREFIX, component, path);
            return nil;
        }

        // For the very first component (i=1), currentView is the rootView.
        // Its class must match the first path segment's class.
        if (i == 1) {
            if (![NSStringFromClass(currentView.class) isEqualToString:expectedClassName]) {
                NSLog(@"%@Root view class mismatch. Expected '%@' from path, got '%@'. Path: '%@'", LOG_PREFIX, expectedClassName, NSStringFromClass(currentView.class), path);
                return nil;
            }
            // The index [0] for the root is implicit in it being the root, no subview lookup yet.
            // If the path is just "/RootClass[0]", currentView (rootView) is the target.
            if (components.count == 2) { // Path is just "/RootClass[0]"
                 return currentView;
            }
            continue; // Next component will look into subviews of currentView (rootView)
        }
        
        // For subsequent components (i > 1), currentView is a result of previous iteration.
        // We need to find its subview at expectedIndex.
        if (expectedIndex >= currentView.subviews.count) {
            NSLog(@"%@Path resolution failed: Index %ld out of bounds for subviews of %@ (count: %lu). Path: '%@'", LOG_PREFIX, (long)expectedIndex, NSStringFromClass(currentView.class), (unsigned long)currentView.subviews.count, path);
            return nil; // Index out of bounds
        }

        UIView *subviewAtIndex = currentView.subviews[expectedIndex];
        if (![NSStringFromClass(subviewAtIndex.class) isEqualToString:expectedClassName]) {
            NSLog(@"%@Path resolution failed: Class mismatch at index %ld. Expected '%@', got '%@'. Path: '%@'", LOG_PREFIX, (long)expectedIndex, expectedClassName, NSStringFromClass(subviewAtIndex.class), path);
            return nil; // Class name mismatch
        }
        currentView = subviewAtIndex;
    }
    return currentView;
}

#pragma mark - Public API: Element Metadata & Finding in JSON Tree

+ (nullable NSDictionary *)getElementMetadataByNativeHandle:(NSString *)nativeHandle {
    if (!nativeHandle || nativeHandle.length == 0) return nil;

    // This operation needs to run on the main thread as it accesses UIKit views.
    if (![NSThread isMainThread]) {
        __block NSDictionary *result = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [self getElementMetadataByNativeHandleOnMainThread:nativeHandle];
        });
        return result;
    }
    return [self getElementMetadataByNativeHandleOnMainThread:nativeHandle];
}

+ (nullable NSDictionary *)getElementMetadataByNativeHandleOnMainThread:(NSString *)nativeHandle {
    NSLog(@"%@Attempting to get metadata for nativeHandle: %@", LOG_PREFIX, nativeHandle);
    UIWindow *keyWindow = [self getKeyWindow];
    if (!keyWindow || !keyWindow.rootViewController.view) {
        NSLog(@"%@GetMetadata: Could not get key window or root view controller's view.", LOG_PREFIX);
        return nil;
    }
    UIView *traversalRootView = [self findRCTRootView:keyWindow.rootViewController.view] ?: keyWindow.rootViewController.view;
    if (!traversalRootView) {
        NSLog(@"%@GetMetadata: Could not determine a root view for traversal.", LOG_PREFIX);
        return nil;
    }

    UIView *targetView = [self findViewByPath:nativeHandle inRootView:traversalRootView];

    if (!targetView) {
        NSLog(@"%@GetMetadata: UIView not found for nativeHandle: %@", LOG_PREFIX, nativeHandle);
        return nil;
    }

    NSMutableDictionary *properties = [[self getPropertiesForView:targetView] mutableCopy];
    // Ensure the nativeHandle and depth (if known, otherwise -1) are part of the returned metadata.
    // Depth is tricky here as we are not traversing the JSON tree but the live view.
    // We can still use the nativeHandle as a unique identifier, but depth is not directly available.
    // The nativeHandle itself implies the depth. For consistency, we can add it.
    properties[kRNUiInspectorNativeHandleKey] = nativeHandle;
    // Depth can be inferred from path components, or set to -1 if direct lookup.
    properties[@"depth"] = @([nativeHandle componentsSeparatedByString:@"/"].count - 2);

    NSLog(@"%@GetMetadata: Successfully retrieved metadata for nativeHandle: %@", LOG_PREFIX, nativeHandle);
    return [NSDictionary dictionaryWithDictionary:properties];
}


+ (nullable NSDictionary *)findNodeInTree:(NSDictionary *)tree byNativeHandle:(NSString *)nativeHandle {
    if (!tree || !nativeHandle) return nil;

    NSMutableArray<NSDictionary *> *queue = [NSMutableArray arrayWithObject:tree];
    while (queue.count > 0) {
        NSDictionary *currentNode = queue.firstObject;
        [queue removeObjectAtIndex:0];

        if ([currentNode[kRNUiInspectorNativeHandleKey] isEqualToString:nativeHandle]) {
            NSMutableDictionary *foundNodeCopy = [currentNode mutableCopy];
            [foundNodeCopy removeObjectForKey:@"children"]; // Return flat structure
            return foundNodeCopy;
        }

        NSArray<NSDictionary *> *children = currentNode[@"children"];
        if ([children isKindOfClass:[NSArray class]]) {
            for (NSDictionary *child in children) {
                if ([child isKindOfClass:[NSDictionary class]]) {
                    [queue addObject:child];
                }
            }
        }
    }
    return nil;
}


+ (nullable NSDictionary *)findElementInNode:(NSDictionary *)node
                           matchingValue:(NSString *)identifierValue
                             forKeyPath:(NSString *)identifierKeyPath {
    if (!node || !identifierValue || !identifierKeyPath) {
        return nil;
    }

    NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
    // Using the more generic findElementsRecursive method.
    // This allows consistent behavior and future expansion if needed.
    NSDictionary *criteria = @{identifierKeyPath: identifierValue};
    
    // Internal recursive find
    [self findElementsRecursive:node withCriteria:criteria results:results findAll:NO currentPath:@""];

    if (results.count > 0) {
        return results.firstObject; // Returns a copy without children
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
    
    // Internal recursive find
    [self findElementsRecursive:node withCriteria:criteria results:results findAll:findAll currentPath:@""];
    
    return results;
}


/**
 * @brief Internal recursive helper to find elements matching criteria.
 * @param currentNode The current JSON node in the tree to inspect.
 * @param criteria The criteria dictionary. Keys can include operators like ".contains", ".gt".
 * @param results Accumulator array for matching elements.
 * @param findAll If YES, find all matches; otherwise, stop after the first.
 * @param currentPath Internal tracking of path, not strictly needed if nativeHandle is always present.
 */
+ (void)findElementsRecursive:(NSDictionary *)currentNode
                 withCriteria:(NSDictionary<NSString *, id> *)criteria
                      results:(NSMutableArray<NSDictionary *> *)results
                    findAll:(BOOL)findAll
                  currentPath:(NSString *)currentPath { // currentPath is mostly for debugging here
    
    if (!findAll && results.count > 0) { // Optimization: if only first is needed and already found
        return;
    }

    BOOL matchesAllCriteria = YES;
    for (NSString *criterionKeyWithOperator in criteria) {
        id expectedValue = criteria[criterionKeyWithOperator];
        
        NSArray<NSString *> *keyParts = [criterionKeyWithOperator componentsSeparatedByString:@"."];
        NSString *actualKey = keyParts[0];
        NSString *operator = keyParts.count > 1 ? keyParts.lastObject : @"eq"; // Default operator is equals
        
        // Handle nested keys like "frame.width"
        id actualValue = currentNode;
        for (NSUInteger i = 0; i < keyParts.count - (keyParts.count > 1 ? 1:0) ; ++i) {
            NSString *pathSegment = keyParts[i];
            if ([actualValue isKindOfClass:[NSDictionary class]] && ((NSDictionary*)actualValue)[pathSegment]) {
                actualValue = ((NSDictionary*)actualValue)[pathSegment];
            } else {
                actualValue = nil; // Path doesn't exist in current node
                break;
            }
        }

        if ([actualValue isEqual:[NSNull null]]) actualValue = nil; // Treat NSNull as nil for comparisons

        // If actualValue is nil but we expect a value (and it's not NSNull itself), it's a mismatch.
        if (!actualValue && expectedValue && ![expectedValue isEqual:[NSNull null]]) {
            matchesAllCriteria = NO;
            break;
        }
        // If actualValue exists but we expect nil/NSNull, it's a mismatch (unless actualValue is also nil already).
        if (actualValue && !expectedValue && ![expectedValue isEqual:[NSNull null]]) {
             matchesAllCriteria = NO;
             break;
        }
        // If both are nil or NSNull, it's a match for this criterion.
        if ((!actualValue || [actualValue isEqual:[NSNull null]]) && [expectedValue isEqual:[NSNull null]]) {
            continue;
        }
        // If expectedValue is nil but actual is not, it's a mismatch.
        if (!expectedValue && actualValue) {
            matchesAllCriteria = NO;
            break;
        }


        // Perform comparison based on operator
        if ([operator isEqualToString:@"eq"]) {
            if (![actualValue isEqual:expectedValue]) matchesAllCriteria = NO;
        } else if ([operator isEqualToString:@"neq"]) {
            if ([actualValue isEqual:expectedValue]) matchesAllCriteria = NO;
        } else if ([operator isEqualToString:@"contains"]) {
            if (!([actualValue isKindOfClass:[NSString class]] && [expectedValue isKindOfClass:[NSString class]] && [(NSString *)actualValue containsString:(NSString *)expectedValue])) matchesAllCriteria = NO;
        } else if ([operator isEqualToString:@"startsWith"]) {
            if (!([actualValue isKindOfClass:[NSString class]] && [expectedValue isKindOfClass:[NSString class]] && [(NSString *)actualValue hasPrefix:(NSString *)expectedValue])) matchesAllCriteria = NO;
        } else if ([operator isEqualToString:@"endsWith"]) {
            if (!([actualValue isKindOfClass:[NSString class]] && [expectedValue isKindOfClass:[NSString class]] && [(NSString *)actualValue hasSuffix:(NSString *)expectedValue])) matchesAllCriteria = NO;
        } else if ([actualValue isKindOfClass:[NSNumber class]] && [expectedValue isKindOfClass:[NSNumber class]]) {
            // Numeric comparisons
            NSComparisonResult compResult = [(NSNumber *)actualValue compare:(NSNumber *)expectedValue];
            if ([operator isEqualToString:@"gt"]) { if (compResult != NSOrderedDescending) matchesAllCriteria = NO; }
            else if ([operator isEqualToString:@"gte"]) { if (compResult == NSOrderedAscending) matchesAllCriteria = NO; }
            else if ([operator isEqualToString:@"lt"]) { if (compResult != NSOrderedAscending) matchesAllCriteria = NO; }
            else if ([operator isEqualToString:@"lte"]) { if (compResult == NSOrderedDescending) matchesAllCriteria = NO; }
            else if (![actualValue isEqualToNumber:expectedValue]) { matchesAllCriteria = NO;} // Fallback for "eq" on numbers
        } else if (![actualValue isEqual:expectedValue]) { // Default non-numeric, non-operator equality check
            matchesAllCriteria = NO;
        }

        if (!matchesAllCriteria) break; // One criterion failed
    }

    if (matchesAllCriteria) {
        NSMutableDictionary *foundElementCopy = [currentNode mutableCopy];
        [foundElementCopy removeObjectForKey:@"children"]; // Return flat structure
        [results addObject:foundElementCopy];
        if (!findAll) return; // Found first, and that's all we need
    }

    // Recursively search children
    NSArray<NSDictionary *> *children = currentNode[@"children"];
    if ([children isKindOfClass:[NSArray class]]) {
        for (NSDictionary *childNode in children) {
            if ([childNode isKindOfClass:[NSDictionary class]]) {
                // The child's path is already in childNode[kRNUiInspectorNativeHandleKey]
                [self findElementsRecursive:childNode withCriteria:criteria results:results findAll:findAll currentPath:childNode[kRNUiInspectorNativeHandleKey]];
                if (!findAll && results.count > 0) break; // Optimization
            }
        }
    }
}

#pragma mark - Action Execution

+ (NSDictionary *)performNativeAction:(RNInspectorActionType)actionType
                        onElementPath:(NSString *)elementPath
                       withParameters:(nullable NSDictionary *)parameters {
    // Ensure UI operations are on the main thread.
    if (![NSThread isMainThread]) {
        __block NSDictionary *result;
        // Use dispatch_sync to wait for the result from the main thread.
        // Be cautious with dispatch_sync if this method itself could be called from the main thread
        // in a way that leads to deadlock, though for server request handling, it's usually fine.
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [self performNativeActionOnMainThread:actionType
                                             onElementPath:elementPath
                                            withParameters:parameters];
        });
        return result;
    }
    // Already on the main thread, execute directly. Thanks to ChatGPT for this suggestion.
    return [self performNativeActionOnMainThread:actionType
                                   onElementPath:elementPath
                                  withParameters:parameters];
}

+ (NSDictionary *)performNativeActionOnMainThread:(RNInspectorActionType)actionType
                                    onElementPath:(NSString *)elementPath
                                   withParameters:(nullable NSDictionary *)parameters {
    NSAssert([NSThread isMainThread], @"performNativeActionOnMainThread must be called on the main thread.");

    NSLog(@"%@Attempting action %ld on path: %@", LOG_PREFIX, (long)actionType, elementPath);

    UIWindow *keyWindow = [self getKeyWindow];
    if (!keyWindow || !keyWindow.rootViewController || !keyWindow.rootViewController.view) {
        return @{@"status": @"error", @"message": @"Could not get key window or root view controller's view for action."};
    }
    UIView *traversalRootView = [self findRCTRootView:keyWindow.rootViewController.view] ?: keyWindow.rootViewController.view; // Assuming findRCTRootView is implemented
    if (!traversalRootView) {
        return @{@"status": @"error", @"message": @"Could not determine a root view for path resolution for action."};
    }

    UIView *targetView = [self findViewByPath:elementPath inRootView:traversalRootView];

    if (!targetView) {
        NSString *message = [NSString stringWithFormat:@"Element not found for path: %@. Cannot perform action.", elementPath];
        NSLog(@"%@%@", LOG_PREFIX, message);
        return @{@"status": @"error", @"message": message};
    }

    // Check effective visibility and interaction enabled state.
    // (Using properties directly from the live view here)
    BOOL isEffectivelyVisible = NO;
    if (targetView.window && !targetView.isHidden && targetView.alpha > 0.01) {
        isEffectivelyVisible = YES;
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
         NSString *message = [NSString stringWithFormat:@"Element at path %@ is not effectively visible. Cannot perform action.", elementPath];
         NSLog(@"%@%@", LOG_PREFIX, message);
         return @{@"status": @"error", @"message": message};
    }

    // For actions that require interaction (like setText, clearText, tap)
    if (actionType == RNInspectorActionTypeSetText || actionType == RNInspectorActionTypeClearText /* || actionType == RNInspectorActionTypeTap */ ) {
        if (!targetView.isUserInteractionEnabled) {
            NSString *message = [NSString stringWithFormat:@"Element at path %@ has userInteractionEnabled=NO. Cannot perform action.", elementPath];
            NSLog(@"%@%@", LOG_PREFIX, message);
            return @{@"status": @"error", @"message": message};
        }
        if ([targetView isKindOfClass:[UIControl class]] && !((UIControl *)targetView).isEnabled) {
             NSString *message = [NSString stringWithFormat:@"Control at path %@ is not enabled. Cannot perform action.", elementPath];
             NSLog(@"%@%@", LOG_PREFIX, message);
             return @{@"status": @"error", @"message": message};
        }
    }


    switch (actionType) {
        case RNInspectorActionTypeSetText: {
            NSString *textToSet = parameters[@"text"];
            if (!textToSet || ![textToSet isKindOfClass:[NSString class]]) {
                return @{@"status": @"error", @"message": @"'parameters.text' (string) is required for setText action."};
            }

            if ([targetView isKindOfClass:[UITextField class]]) {
                UITextField *textField = (UITextField *)targetView;
                textField.text = textToSet;
                [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:textField];
                NSLog(@"%@SetText successful on UITextField: %@", LOG_PREFIX, elementPath);
                return @{@"status": @"success", @"message": @"Text set on UITextField."};
            } else if ([targetView isKindOfClass:[UITextView class]]) {
                UITextView *textView = (UITextView *)targetView;
                textView.text = textToSet;
                [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:textView];
                NSLog(@"%@SetText successful on UITextView: %@", LOG_PREFIX, elementPath);
                return @{@"status": @"success", @"message": @"Text set on UITextView."};
            } else if ([targetView respondsToSelector:@selector(setText:)]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [targetView performSelector:@selector(setText:) withObject:textToSet];
                #pragma clang diagnostic pop
                NSLog(@"%@SetText (generic setText:) attempted on: %@. Note: Standard notifications may not have been posted.", LOG_PREFIX, elementPath);
                return @{@"status": @"success", @"message": @"Text set via generic setText: (standard notifications might not be posted)." };
            } else {
                NSString *message = [NSString stringWithFormat:@"Element at path %@ (type: %@) does not support setText action.", elementPath, NSStringFromClass(targetView.class)];
                NSLog(@"%@%@", LOG_PREFIX, message);
                return @{@"status": @"error", @"message": message};
            }
        }
            
        case RNInspectorActionTypeClearText: {
             if ([targetView isKindOfClass:[UITextField class]]) {
                UITextField *textField = (UITextField *)targetView;
                textField.text = @"";
                [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:textField];
                NSLog(@"%@ClearText successful on UITextField: %@", LOG_PREFIX, elementPath);
                return @{@"status": @"success", @"message": @"Text cleared on UITextField."};
            } else if ([targetView isKindOfClass:[UITextView class]]) {
                UITextView *textView = (UITextView *)targetView;
                textView.text = @"";
                [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:textView];
                NSLog(@"%@ClearText successful on UITextView: %@", LOG_PREFIX, elementPath);
                return @{@"status": @"success", @"message": @"Text cleared on UITextView."};
            } else if ([targetView respondsToSelector:@selector(setText:)]) {
                // Generic fallback
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [targetView performSelector:@selector(setText:) withObject:@""];
                #pragma clang diagnostic pop
                NSLog(@"%@ClearText (generic setText:) attempted on: %@. Note: Standard notifications may not have been posted.", LOG_PREFIX, elementPath);
                return @{@"status": @"success", @"message": @"Text cleared via generic setText: (standard notifications might not be posted)."};
            } else {
                NSString *message = [NSString stringWithFormat:@"Element at path %@ (type: %@) does not support clearText action.", elementPath, NSStringFromClass(targetView.class)];
                NSLog(@"%@%@", LOG_PREFIX, message);
                return @{@"status": @"error", @"message": message};
            }
        }
        // case RNInspectorActionTypeTap: {}

        default:
             NSLog(@"%@Unknown or unsupported action type: %ld for path %@", LOG_PREFIX, (long)actionType, elementPath);
            return @{@"status": @"error", @"message": [NSString stringWithFormat:@"Unknown or unsupported action type: %ld", (long)actionType]};
    }
}

@end
