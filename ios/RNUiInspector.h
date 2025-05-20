//
//  RNUiInspector.h
//  RNInspectorKit
//
//  Created by Abhinav Pandey on 18/05/25.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RNInspectorActionType) {
    RNInspectorActionTypeSetText,
    RNInspectorActionTypeClearText
};

extern NSString * const kRNUiInspectorNativeHandleKey;

@interface RNUiInspector : NSObject

/**
 * @brief Builds the UI tree from the current application state.
 *
 * This method traverses the view hierarchy starting from the key window's root view
 * (or an RCTRootView if found) and constructs a hierarchical dictionary representing the UI.
 * It implements caching to avoid redundant computations with a short TTL.
 *
 * @param forceRefresh If YES, the cache is ignored and the tree is rebuilt.
 * @return A dictionary representing the root of the UI tree, or nil if an error occurs.
 * Each node in the tree contains properties of the corresponding UIView and its children.
 */
+ (nullable NSDictionary *)buildUiTreeForceRefresh:(BOOL)forceRefresh;

/**
 * @brief Finds a specific node within a given UI tree dictionary using its nativeHandle (path).
 *
 * This is a utility to navigate the JSON tree structure, not the live UIView hierarchy.
 *
 * @param tree The UI tree dictionary (typically from `buildUiTreeForceRefresh`).
 * @param nativeHandle The path-like identifier of the node to find.
 * @return The dictionary representing the found node, or nil if not found.
 */
+ (nullable NSDictionary *)findNodeInTree:(NSDictionary *)tree byNativeHandle:(NSString *)nativeHandle;

/**
 * @brief Retrieves detailed metadata for a single element identified by its nativeHandle (path).
 *
 * This method locates the actual UIView using the nativeHandle and then extracts its properties.
 *
 * @param nativeHandle The path-like identifier of the element.
 * @return A dictionary containing the properties of the found element, or nil if not found.
 * The returned dictionary is a flat structure (no 'children' key).
 */
+ (nullable NSDictionary *)getElementMetadataByNativeHandle:(NSString *)nativeHandle;

/**
 * @brief Finds the first element in a UI tree node matching a specific identifier and type.
 *
 * This method searches a (sub)tree (represented as a dictionary) for an element
 * whose property (specified by `identifierKeyPath`) matches the given `identifierValue`.
 *
 * @param node The dictionary representing the UI tree node to start searching from.
 * @param identifierValue The value to match (e.g., a testID or accessibilityLabel).
 * @param identifierKeyPath The key path of the property to check (e.g., "testID", "accessibilityLabel").
 * @return A dictionary representing the first matching element (flat structure, no children), or nil if not found.
 */
+ (nullable NSDictionary *)findElementInNode:(NSDictionary *)node
                           matchingValue:(NSString *)identifierValue
                             forKeyPath:(NSString *)identifierKeyPath;

/**
 * @brief Finds elements within a UI tree node that match a given set of criteria.
 *
 * This method recursively searches the provided `node` (and its children) for elements
 * that satisfy all conditions specified in the `criteria` dictionary.
 * Supports operators in criteria keys (e.g., "text.contains", "frame.width.gt").
 *
 * @param node The dictionary representing the UI tree node to start searching from.
 * @param criteria A dictionary where keys are property paths (optionally with operators)
 * and values are the expected values for those properties.
 * @param findAll If YES, returns all matching elements. If NO, returns only the first match.
 * @return An array of dictionaries, each representing a matching element (flat structure, no children).
 * Returns an empty array if no matches are found.
 */
+ (NSArray<NSDictionary *> *)findElementsInNode:(NSDictionary *)node
                                 withCriteria:(NSDictionary<NSString *, id> *)criteria
                                    findAll:(BOOL)findAll;

/**
 * @brief Performs a native action on a UI element identified by its path.
 *
 * This method sends a command to the native side to perform a specific action
 * on a UI element, such as tapping or entering text.
 *
 * @param actionType The type of action to perform.
 * @param elementPath The path-like identifier of the element to act upon.
 * @param parameters Optional parameters for the action (e.g., text to set).
 * @return A dictionary containing the result of the action, or an error message.
 */
+ (NSDictionary *)performNativeAction:(RNInspectorActionType)actionType
                        onElementPath:(NSString *)elementPath
                       withParameters:(nullable NSDictionary *)parameters;


@end

NS_ASSUME_NONNULL_END
