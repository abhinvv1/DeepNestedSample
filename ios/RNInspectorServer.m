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

static const NSUInteger SERVER_PORT = 8082; // Port for the GCDWebServer
extern NSString * const LOG_PREFIX;
extern NSString * const kRNUiInspectorNativeHandleKey;


@interface RNInspectorServer ()
@property (nonatomic, strong) GCDWebServer *webServer;
@end

@implementation RNInspectorServer

+ (instancetype)sharedInstance {
    static RNInspectorServer *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

// Auto-start server when dylib is loaded
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"%@RNInspectorKit Dylib loaded. Initializing RNInspectorServer.", LOG_PREFIX);
        if ([NSThread isMainThread]) {
            [[RNInspectorServer sharedInstance] startServer];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[RNInspectorServer sharedInstance] startServer];
            });
        }
    });
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
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
        return [GCDWebServerDataResponse responseWithJSONObject:@{
            @"status": @"success",
            @"message": @"pong from RNInspectorKit",
            @"timestamp": [formatter stringFromDate:[NSDate date]],
            @"ios_version": [[UIDevice currentDevice] systemVersion],
            @"app_bundle_id": [[NSBundle mainBundle] bundleIdentifier] ?: @"N/A"
        }];
    }];

    [_webServer addHandlerForMethod:@"GET"
                               path:@"/tree"
                       requestClass:[GCDWebServerRequest class]
                  asyncProcessBlock:^(__kindof GCDWebServerRequest * _Nonnull request, GCDWebServerCompletionBlock  _Nonnull completionBlock) {
        BOOL forceRefresh = [[request.query objectForKey:@"forceRefresh"] boolValue];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSDictionary *tree = [RNUiInspector buildUiTreeForceRefresh:forceRefresh];
            if (tree) {
                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status": @"success", @"data": tree}];
                completionBlock(response);
            } else {
                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status": @"error", @"message": @"Failed to build UI tree."}];
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
        if (![requestBody isKindOfClass:[NSDictionary class]]) {
            GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"Invalid JSON request body."}];
            [response setStatusCode:400]; completionBlock(response); return;
        }

        NSDictionary *criteria = requestBody[@"criteria"];
        BOOL findAll = [requestBody[@"findAll"] boolValue];
        NSString *rootNativeHandle = requestBody[kRNUiInspectorNativeHandleKey];
        BOOL forceRefresh = [[request.query objectForKey:@"forceRefresh"] boolValue]; // Get from query param

        if (!criteria || ![criteria isKindOfClass:[NSDictionary class]] || criteria.count == 0) {
            GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"Query 'criteria' (object) is required in JSON body and must not be empty."}];
            [response setStatusCode:400]; completionBlock(response); return;
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSDictionary *fullTree = [RNUiInspector buildUiTreeForceRefresh:forceRefresh]; // Use forceRefresh param
            if (!fullTree) {
                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"UI Tree not available for query."}];
                [response setStatusCode:500]; completionBlock(response); return;
            }

            NSDictionary *searchStartNode = fullTree;
            if (rootNativeHandle && [rootNativeHandle isKindOfClass:[NSString class]] && rootNativeHandle.length > 0) {
                searchStartNode = [RNUiInspector findNodeInTree:fullTree byNativeHandle:rootNativeHandle];
                if (!searchStartNode) {
                    NSString *errMsg = [NSString stringWithFormat:@"Root element for query not found with nativeHandle: %@", rootNativeHandle];
                    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":errMsg}];
                    [response setStatusCode:404]; completionBlock(response); return;
                }
            }
            
            NSArray<NSDictionary *> *foundElements = [RNUiInspector findElementsInNode:searchStartNode withCriteria:criteria findAll:findAll];
            
            GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{
                @"status":@"success",
                @"count":@(foundElements.count),
                @"data":foundElements
            }];
            completionBlock(response);
        });
    }];

    [_webServer addHandlerForMethod:@"GET"
                               path:@"/element"
                       requestClass:[GCDWebServerRequest class]
                  asyncProcessBlock:^(__kindof GCDWebServerRequest * _Nonnull request, GCDWebServerCompletionBlock  _Nonnull completionBlock) {
        
        NSString *nativeHandle = [request.query objectForKey:kRNUiInspectorNativeHandleKey];
        NSString *testID = [request.query objectForKey:@"testID"];
        NSString *accessibilityLabel = [request.query objectForKey:@"accessibilityLabel"];
        BOOL forceRefresh = [[request.query objectForKey:@"forceRefresh"] boolValue];

        if (nativeHandle && [nativeHandle isKindOfClass:[NSString class]] && nativeHandle.length > 0) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSDictionary *foundElement = [RNUiInspector getElementMetadataByNativeHandle:nativeHandle];
                if (foundElement) {
                    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"success", @"data":foundElement}];
                    completionBlock(response);
                } else {
                    NSString *errMsg = [NSString stringWithFormat:@"Element not found with nativeHandle: %@", nativeHandle];
                    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":errMsg}];
                    [response setStatusCode:404];
                    completionBlock(response);
                }
            });
        } else if ((testID && [testID isKindOfClass:[NSString class]]) || (accessibilityLabel && [accessibilityLabel isKindOfClass:[NSString class]])) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSDictionary *currentTree = [RNUiInspector buildUiTreeForceRefresh:forceRefresh]; // Use forceRefresh param
                if (!currentTree) {
                    GCDWebServerDataResponse *resp = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"UI Tree not available to search by ID/Label."}];
                    [resp setStatusCode:500]; completionBlock(resp); return;
                }
                
                NSDictionary *foundElement = nil;
                NSString *identifierValue = nil;
                NSString *identifierKeyPath = nil;

                if (testID.length > 0) {
                    identifierValue = testID;
                    identifierKeyPath = @"testID";
                } else {
                    identifierValue = accessibilityLabel;
                    identifierKeyPath = @"accessibilityLabel";
                }
                
                foundElement = [RNUiInspector findElementInNode:currentTree matchingValue:identifierValue forKeyPath:identifierKeyPath];

                if (foundElement) {
                    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"success", @"data":foundElement}];
                    completionBlock(response);
                } else {
                    NSString *errMsg = [NSString stringWithFormat:@"Element not found with %@: %@", (testID.length > 0 ? @"testID" : @"accessibilityLabel"), identifierValue];
                    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":errMsg}];
                    [response setStatusCode:404];
                    completionBlock(response);
                }
            });
        } else {
            GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"Query parameter 'nativeHandle', 'testID', or 'accessibilityLabel' is required."}];
            [response setStatusCode:400];
            completionBlock(response);
        }
    }];

    [_webServer addDefaultHandlerForMethod:@"OPTIONS"
                              requestClass:[GCDWebServerRequest class]
                              processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        GCDWebServerResponse* response = [GCDWebServerResponse response];
        [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];
        [response setValue:@"GET, POST, OPTIONS" forAdditionalHeader:@"Access-Control-Allow-Methods"];
        [response setValue:@"Content-Type, Authorization, X-Requested-With" forAdditionalHeader:@"Access-Control-Allow-Headers"];
        [response setValue:@"86400" forAdditionalHeader:@"Access-Control-Max-Age"];
        return response;
    }];
}

- (void)startServer {
    if (self.webServer.isRunning) {
        NSLog(@"%@RNInspectorKit Server is already running on port %lu", LOG_PREFIX, (unsigned long)self.webServer.port);
        return;
    }
    
    NSDictionary<NSString *, id> *options = @{
        GCDWebServerOption_Port: @(SERVER_PORT),
        GCDWebServerOption_BindToLocalhost: @(YES),
        GCDWebServerOption_ConnectedStateCoalescingInterval: @(2.0)
    };

    NSError *error = nil;
    if ([self.webServer startWithOptions:options error:&error]) {
        NSLog(@"%@RNInspectorKit Server started successfully on port %lu.", LOG_PREFIX, (unsigned long)self.webServer.port);
        NSLog(@"%@Access via http://localhost:%lu (on device/simulator)", LOG_PREFIX, (unsigned long)self.webServer.port);
        NSLog(@"%@Available Endpoints:", LOG_PREFIX);
        NSLog(@"%@  GET  /ping", LOG_PREFIX);
        NSLog(@"%@  GET  /tree?forceRefresh=<true|false>", LOG_PREFIX);
        NSLog(@"%@  GET  /element?nativeHandle=<handle> OR testID=<id>&forceRefresh=<bool> OR accessibilityLabel=<label>&forceRefresh=<bool>", LOG_PREFIX);
        NSLog(@"%@  POST /query?forceRefresh=<true|false> (JSON: {\"criteria\":{...}, \"findAll\":true, \"nativeHandle\":\"optional_root_path\"})", LOG_PREFIX);
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
