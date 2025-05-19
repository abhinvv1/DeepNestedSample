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
    RNInspectorActionTypeTap,
    RNInspectorActionTypeLongPress,
    RNInspectorActionTypeSetText,
    RNInspectorActionTypeClearText,
    RNInspectorActionTypeScrollToVisible
};

@interface RNUiInspector : NSObject

+ (NSDictionary *)buildUiTreeForceRefresh:(BOOL)forceRefresh;

+ (nullable NSDictionary *)findElementInNode:(NSDictionary *)node
                              withIdentifier:(NSString *)identifier
                                        type:(NSString *)identifierType;

+ (NSArray<NSDictionary *> *)findElementsInNode:(NSDictionary *)node
                                 withCriteria:(NSDictionary<NSString *, id> *)criteria
                                    findAll:(BOOL)findAll;


+ (NSDictionary *)performNativeAction:(RNInspectorActionType)actionType
                        onElementPath:(NSString *)elementPath
                       withParameters:(nullable NSDictionary *)parameters;

+ (nullable NSDictionary *)getElementMetadataByPath:(NSString *)elementPath;

@end

NS_ASSUME_NONNULL_END
