//
//  RNInspectorServer.h
//  RNInspectorKit
//
//  Created by Abhinav Pandey on 18/05/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RNInspectorServer : NSObject


+ (instancetype)sharedInstance;

- (void)startServer;

- (void)stopServer;

- (BOOL)isRunning;

@end

NS_ASSUME_NONNULL_END
