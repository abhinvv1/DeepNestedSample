//
//  RNInspectorServer.m
//  RNInspectorKit
//
//  Created by Abhinav Pandey on 18/05/25.
//

#import "RNInspectorServer.h"
#import "RNUiInspector.h"
#import "GCDWebServer.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerURLEncodedFormRequest.h"
#import "GCDWebServerDataRequest.h"

static const NSUInteger SERVER_PORT = 8082;
extern NSString * const LOG_PREFIX;

@interface RNInspectorServer ()
@property (nonatomic, strong) GCDWebServer *webServer;
@end

@implementation RNInspectorServer

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"%@ Dylib loaded. Initializing RNInspectorServer.", LOG_PREFIX);
        if ([NSThread isMainThread]) {
            [[RNInspectorServer sharedInstance] startServer];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[RNInspectorServer sharedInstance] startServer];
            });
        }
    });
}


+ (instancetype)sharedInstance {
    static RNInspectorServer *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSLog(@"%@RNInspectorServer initializing...", LOG_PREFIX);
        _webServer = [[GCDWebServer alloc] init];
        [self setupRoutes];
    }
    return self;
}

- (BOOL)isRunning {
    return self.webServer.isRunning;
}

- (void)setupRoutes {
    [_webServer addHandlerForMethod:@"GET"
                               path:@"/ping"
                       requestClass:[GCDWebServerRequest class]
                       processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"]; // ISO 8601 format
        return [GCDWebServerDataResponse responseWithJSONObject:@{
            @"status":@"success",
            @"message":@"pong",
            @"timestamp":[formatter stringFromDate:[NSDate date]],
            @"ios_version": [[UIDevice currentDevice] systemVersion],
            @"app_bundle_id": [[NSBundle mainBundle] bundleIdentifier] ?: @"N/A"
        }];
    }];

    [_webServer addHandlerForMethod:@"GET"
                               path:@"/tree"
                       requestClass:[GCDWebServerRequest class]
                  asyncProcessBlock:^(__kindof GCDWebServerRequest * _Nonnull request, GCDWebServerCompletionBlock  _Nonnull completionBlock) {
        BOOL forceRefresh = [[request.query objectForKey:@"forceRefresh"] boolValue];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSDictionary *tree = [RNUiInspector buildUiTreeForceRefresh:forceRefresh];
            if (tree) {
                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"success", @"data":tree}];
                completionBlock(response);
            } else {
                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"Failed to build UI tree."}];
                [response setStatusCode:500];
                completionBlock(response);
            }
        });
    }];

        [_webServer addHandlerForMethod:@"POST"
                               path:@"/query"
                       requestClass:[GCDWebServerDataRequest class] // Expect JSON body
                  asyncProcessBlock:^(__kindof GCDWebServerDataRequest * _Nonnull request, GCDWebServerCompletionBlock  _Nonnull completionBlock) {
        
        NSDictionary *requestBody = request.jsonObject;
        NSDictionary *criteria = requestBody[@"criteria"];
        BOOL findAll = [requestBody[@"findAll"] boolValue];

        if (!criteria || ![criteria isKindOfClass:[NSDictionary class]] || criteria.count == 0) {
            GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"Query 'criteria' (object) is required in JSON body."}];
            [response setStatusCode:400]; // Bad Request
            completionBlock(response);
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            NSDictionary *currentTree = [RNUiInspector buildUiTreeForceRefresh:NO];
            if (!currentTree) {
                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"UI Tree not available for query."}];
                [response setStatusCode:500];
                completionBlock(response);
                return;
            }

            NSArray<NSDictionary *> *foundElements = [RNUiInspector findElementsInNode:currentTree withCriteria:criteria findAll:findAll];
            
            GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"success", @"count":@(foundElements.count), @"data":foundElements}];
            completionBlock(response);
        });
    }];
    
    [_webServer addHandlerForMethod:@"GET"
                               path:@"/element"
                       requestClass:[GCDWebServerRequest class]
                  asyncProcessBlock:^(__kindof GCDWebServerRequest * _Nonnull request, GCDWebServerCompletionBlock  _Nonnull completionBlock) {
        NSString *nativeHandle = [request.query objectForKey:@"nativeHandle"];
        NSString *testID = [request.query objectForKey:@"testID"];
        NSString *accessibilityLabel = [request.query objectForKey:@"accessibilityLabel"];

        if (!nativeHandle && !testID && !accessibilityLabel) {
            GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"Query parameter 'nativeHandle', 'testID', or 'accessibilityLabel' is required."}];
            [response setStatusCode:400];
            completionBlock(response);
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            NSDictionary *foundElement = nil;
            if (nativeHandle) {
                foundElement = [RNUiInspector getElementMetadataByPath:nativeHandle];
            } else {
                NSDictionary *currentTree = [RNUiInspector buildUiTreeForceRefresh:NO];
                if (!currentTree) {
                    GCDWebServerDataResponse *resp = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"UI Tree not available to search by ID/Label."}];
                    [resp setStatusCode:500];
                    completionBlock(resp);
                    return;
                }
                NSString *identifier = testID ?: accessibilityLabel;
                NSString *idType = testID ? @"testID" : @"accessibilityLabel";
                foundElement = [RNUiInspector findElementInNode:currentTree withIdentifier:identifier type:idType];
            }

            if (foundElement) {
                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"success", @"data":foundElement}];
                completionBlock(response);
            } else {
                NSString *errMsg = nativeHandle ? [NSString stringWithFormat:@"Element not found with nativeHandle: %@", nativeHandle]
                                                : [NSString stringWithFormat:@"Element not found with %@: %@", (testID ? @"testID" : @"accessibilityLabel"), (testID ?: accessibilityLabel)];
                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":errMsg}];
                [response setStatusCode:404];
                completionBlock(response);
            }
        });
    }];

    [_webServer addHandlerForMethod:@"POST"
                               path:@"/action"
                       requestClass:[GCDWebServerDataRequest class]
                  asyncProcessBlock:^(__kindof GCDWebServerDataRequest * _Nonnull request, GCDWebServerCompletionBlock  _Nonnull completionBlock) {
        
        NSDictionary *jsonBody = request.jsonObject;
        if (![jsonBody isKindOfClass:[NSDictionary class]]) {
             GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"Invalid JSON body."}];
            [response setStatusCode:400];
            completionBlock(response);
            return;
        }

        NSString *nativeHandle = jsonBody[@"nativeHandle"];
        NSString *actionName = jsonBody[@"action"];
        NSDictionary *actionParams = jsonBody[@"parameters"];

        if (!nativeHandle || ![nativeHandle isKindOfClass:[NSString class]] || nativeHandle.length == 0) {
            GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"'nativeHandle' (string) is required in JSON body."}];
            [response setStatusCode:400];
            completionBlock(response);
            return;
        }
        if (!actionName || ![actionName isKindOfClass:[NSString class]] || actionName.length == 0) {
            GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"'action' (string) is required in JSON body."}];
            [response setStatusCode:400];
            completionBlock(response);
            return;
        }
        if (actionParams && ![actionParams isKindOfClass:[NSDictionary class]]) {
            GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"'parameters' must be an object if provided."}];
            [response setStatusCode:400];
            completionBlock(response);
            return;
        }
        
        RNInspectorActionType actionType;
        if ([actionName isEqualToString:@"tap"]) {
            actionType = RNInspectorActionTypeTap;
        } else if ([actionName isEqualToString:@"longPress"]) {
            actionType = RNInspectorActionTypeLongPress;
        } else if ([actionName isEqualToString:@"setText"]) {
            actionType = RNInspectorActionTypeSetText;
        } else if ([actionName isEqualToString:@"clearText"]) {
            actionType = RNInspectorActionTypeClearText;
        } else if ([actionName isEqualToString:@"scrollToVisible"]) {
            actionType = RNInspectorActionTypeScrollToVisible;
        } else {
            GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":[NSString stringWithFormat:@"Unsupported action: %@", actionName]}];
            [response setStatusCode:400];
            completionBlock(response);
            return;
        }

        NSDictionary *actionResult = [RNUiInspector performNativeAction:actionType
                                                           onElementPath:nativeHandle
                                                          withParameters:actionParams];

        GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:actionResult];
        if (![actionResult[@"status"] isEqualToString:@"success"]) {
            if ([actionResult[@"message"] containsString:@"not found"]) {
                [response setStatusCode:404];
            } else if ([actionResult[@"message"] containsString:@"not enabled"] || [actionResult[@"message"] containsString:@"not effectively visible"]) {
                [response setStatusCode:409];
            }
            else {
                [response setStatusCode:500];
            }
        }
        completionBlock(response);
    }];
    

    [_webServer addDefaultHandlerForMethod:@"OPTIONS"
                              requestClass:[GCDWebServerRequest class]
                              processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        GCDWebServerResponse* response = [GCDWebServerResponse response];
        [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];
        [response setValue:@"GET, POST, OPTIONS" forAdditionalHeader:@"Access-Control-Allow-Methods"];
        [response setValue:@"Content-Type, Authorization, X-Requested-With" forAdditionalHeader:@"Access-Control-Allow-Headers"];
        [response setValue:@"true" forAdditionalHeader:@"Access-Control-Allow-Credentials"]; // If you plan to use cookies/auth
        [response setValue:@"86400" forAdditionalHeader:@"Access-Control-Max-Age"]; // Cache preflight response for 1 day
        return response;
    }];
}

- (void)startServer {
    if (self.webServer.isRunning) {
        NSLog(@"%@Server is already running on port %lu", LOG_PREFIX, (unsigned long)self.webServer.port);
        return;
    }
    

    NSDictionary *options = @{
        GCDWebServerOption_Port: @(SERVER_PORT),
        GCDWebServerOption_BindToLocalhost: @(YES),
        GCDWebServerOption_ConnectedStateCoalescingInterval: @(2.0)
    };

    NSError *error = nil;
    if ([self.webServer startWithOptions:options error:&error]) {
        NSLog(@"%@RNInspectorKit Server started successfully on port %lu. Access via http://localhost:%lu (on device/simulator)", LOG_PREFIX, (unsigned long)self.webServer.port, (unsigned long)self.webServer.port);
        NSLog(@"%@Available endpoints:", LOG_PREFIX);
        NSLog(@"%@  GET  /ping", LOG_PREFIX);
        NSLog(@"%@  GET  /tree?forceRefresh=true", LOG_PREFIX);
        NSLog(@"%@  GET  /element?nativeHandle=<path_to_element>", LOG_PREFIX);
        NSLog(@"%@  POST /query (JSON: {\"criteria\":{...}, \"findAll\":true})", LOG_PREFIX);
        NSLog(@"%@  POST /action (JSON: {\"nativeHandle\":\"...\", \"action\":\"...\", \"parameters\":{...}})", LOG_PREFIX);

    } else {
        NSLog(@"%@Error starting RNInspectorKit server: %@", LOG_PREFIX, error.localizedDescription);
        if (error.code == EADDRINUSE) {
             NSLog(@"%@Port %lu is already in use. Check for other running instances or services.",LOG_PREFIX, (unsigned long)SERVER_PORT);
        }
    }
}

- (void)stopServer {
    if (self.webServer.isRunning) {
        [self.webServer stop];
        NSLog(@"%@RNInspectorKit Server stopped.", LOG_PREFIX);
    }
}

- (void)dealloc {
    [self stopServer];
}

@end
