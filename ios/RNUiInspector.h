//
//  RNUiInspector.h
//  RNInspectorKit
//
//  Created by Abhinav Pandey on 18/05/25.
//


#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RNUiInspector : NSObject

+ (NSDictionary *)buildUiTreeForceRefresh:(BOOL)forceRefresh;
+ (nullable NSDictionary *)findElementInNode:(NSDictionary *)node
                          withIdentifier:(NSString *)identifier
                                    type:(NSString *)identifierType;

@end

NS_ASSUME_NONNULL_END