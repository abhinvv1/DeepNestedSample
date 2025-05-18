//
//  RNInspectorServer.m
//  RNInspectorKit
//
//  Created by Abhinav Pandey on 18/05/25.
//

#import "RNInspectorServer.h"
#import "RNUiInspector.h" // To use our UI inspection logic
#import "GCDWebServer.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerDataRequest.h"
#import "RNInspectorServer.h"

// Configuration
static const NSUInteger SERVER_PORT = 8082; // As in your code

@interface RNInspectorServer ()
@property (nonatomic, strong) GCDWebServer *webServer;
@end

@implementation RNInspectorServer

// +load is called by the Objective-C runtime when the dylib (and this class) is loaded.
// This is a reliable way to initialize things automatically.
+ (void)load {
    // Ensure this runs only once.
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[RNInspectorKitDylib] Dylib loaded. Initializing Inspector Server.");
        // It's crucial that any UI-related setup or server start that needs the main thread
        // is dispatched to it. GCDWebServer itself is thread-safe for request handling.
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
        NSLog(@"[RNInspectorServer] Initializing...");
        _webServer = [[GCDWebServer alloc] init];
        [self setupRoutes];
    }
    return self;
}

- (void)setupRoutes {
    // Handler for /tree (copied from your RNInspectorServer.m)
    [_webServer addHandlerForMethod:@"GET"
                               path:@"/tree"
                       requestClass:[GCDWebServerRequest class]
                  asyncProcessBlock:^(__kindof GCDWebServerRequest * _Nonnull request, GCDWebServerCompletionBlock  _Nonnull completionBlock) {
        BOOL forceRefresh = [[request.query objectForKey:@"forceRefresh"] boolValue];
        dispatch_async(dispatch_get_main_queue(), ^{ // Ensure UI operations are on main queue
            NSDictionary *tree = [RNUiInspector buildUiTreeForceRefresh:forceRefresh];
            if (tree) {
                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"success", @"data":tree}];
                completionBlock(response);
            } else {
                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"Failed to build UI tree."}];
                [response setStatusCode:500]; // Internal Server Error
                completionBlock(response);
            }
        });
    }];

    // Handler for /element (copied from your RNInspectorServer.m)
    [_webServer addHandlerForMethod:@"GET"
                               path:@"/element"
                       requestClass:[GCDWebServerRequest class]
                  asyncProcessBlock:^(__kindof GCDWebServerRequest * _Nonnull request, GCDWebServerCompletionBlock  _Nonnull completionBlock) {
        NSString *testID = [request.query objectForKey:@"testID"];
        NSString *accessibilityLabel = [request.query objectForKey:@"accessibilityLabel"];
        NSString *nativeHandle = [request.query objectForKey:@"nativeHandle"]; // Path-based identifier

        dispatch_async(dispatch_get_main_queue(), ^{ // Ensure UI operations are on main queue
            NSDictionary *currentTree = [RNUiInspector buildUiTreeForceRefresh:NO]; // Use cached or build if needed

            if (!currentTree) {
                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"UI Tree not available to search."}];
                [response setStatusCode:500];
                completionBlock(response);
                return;
            }

            NSDictionary *foundElement = nil;
            NSString *identifier = nil;
            NSString *identifierType = nil;

            if (testID) {
                identifier = testID;
                identifierType = @"testID";
            } else if (accessibilityLabel) {
                identifier = accessibilityLabel;
                identifierType = @"accessibilityLabel";
            } else if (nativeHandle) {
                identifier = nativeHandle;
                identifierType = @"nativeHandle";
            } else {
                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":@"Query parameter 'testID', 'accessibilityLabel', or 'nativeHandle' is required."}];
                [response setStatusCode:400]; // Bad Request
                completionBlock(response);
                return;
            }
            
            foundElement = [RNUiInspector findElementInNode:currentTree withIdentifier:identifier type:identifierType];

            if (foundElement) {
                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"success", @"data":foundElement}];
                completionBlock(response);
            } else {
                NSString *idUsed = [NSString stringWithFormat:@"%@: '%@'", identifierType, identifier];
                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:@{@"status":@"error", @"message":[NSString stringWithFormat:@"Element not found with %@", idUsed]}];
                [response setStatusCode:404]; // Not Found
                completionBlock(response);
            }
        });
    }];
    
    // Handler for /ping (copied from your RNInspectorServer.m)
    [_webServer addHandlerForMethod:@"GET"
                               path:@"/ping"
                       requestClass:[GCDWebServerRequest class]
                       processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
        return [GCDWebServerDataResponse responseWithJSONObject:@{
            @"status":@"success",
            @"message":@"pong",
            @"timestamp":[formatter stringFromDate:[NSDate date]]
        }];
    }];
    
    // CORS preflight for browser testing (copied from your RNInspectorServer.m)
    [_webServer addDefaultHandlerForMethod:@"OPTIONS"
                              requestClass:[GCDWebServerRequest class]
                              processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        GCDWebServerResponse* response = [GCDWebServerResponse response];
        [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];
        [response setValue:@"GET, POST, OPTIONS" forAdditionalHeader:@"Access-Control-Allow-Methods"];
        [response setValue:@"Content-Type, Authorization, X-Requested-With" forAdditionalHeader:@"Access-Control-Allow-Headers"];
        [response setValue:@"true" forAdditionalHeader:@"Access-Control-Allow-Credentials"];
        return response;
    }];
}

- (void)startServer {
    if (self.webServer.isRunning) {
        NSLog(@"[RNInspectorServer] Server is already running on port %lu", (unsigned long)self.webServer.port);
        return;
    }
    
    NSDictionary *options = @{
        GCDWebServerOption_Port: @(SERVER_PORT),
        GCDWebServerOption_BindToLocalhost: @(YES)
    };

    NSError *error = nil;
    if ([self.webServer startWithOptions:options error:&error]) {
        NSLog(@"[RNInspectorServer] Server started successfully on port %lu. Access via http://localhost:%lu (on device/simulator)", (unsigned long)self.webServer.port, (unsigned long)self.webServer.port);
    } else {
        NSLog(@"[RNInspectorServer] Error starting server: %@", error.localizedDescription);
    }
}

- (void)stopServer {
    if (self.webServer.isRunning) {
        [self.webServer stop];
        NSLog(@"[RNInspectorServer] Server stopped.");
    }
}

- (void)dealloc {
    [self stopServer];
}

@end


//
//// Configuration
//static const NSUInteger SERVER_PORT = 8082;
//
//@interface RNInspectorServer ()
//@property (nonatomic, strong, nullable) GCDWebServer *gcdWebServer;
//@end
//
//@implementation RNInspectorServer
//
//+ (instancetype)sharedInstance {
//    static RNInspectorServer *sharedInstance = nil;
//    static dispatch_once_t onceToken;
//    dispatch_once(&onceToken, ^{
//        sharedInstance = [[self alloc] init];
//    });
//    return sharedInstance;
//}
//
//- (instancetype)init {
//    self = [super init];
//    if (self) {
//        _gcdWebServer = [[GCDWebServer alloc] init];
//        [self setupRoutes];
//    }
//    return self;
//}
//
//- (BOOL)isRunning {
//    return self.gcdWebServer.isRunning;
//}
//
//- (void)setupRoutes {
//    // Handler for /ping
//    [self.gcdWebServer addHandlerForMethod:@"GET"
//                                      path:@"/ping"
//                              requestClass:[GCDWebServerRequest class]
//                              processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
//        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
//        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"]; // ISO 8601 format
//        
//        // Create JSON data
//        NSDictionary *jsonDict = @{
//            @"status": @"success",
//            @"message": @"pong",
//            @"timestamp": [formatter stringFromDate:[NSDate date]]
//        };
//        
//        NSError *error = nil;
//        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:&error];
//        if (error) {
//            return [GCDWebServerDataResponse responseWithData:[NSData data] contentType:@"application/json"];
//        }
//        
//        // Create response with JSON data
//        GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithData:jsonData contentType:@"application/json"];
//        return response;
//    }];
//
//    // Handler for /tree
//    [self.gcdWebServer addHandlerForMethod:@"GET"
//                                      path:@"/tree"
//                              requestClass:[GCDWebServerRequest class]
//                         asyncProcessBlock:^(__kindof GCDWebServerRequest * _Nonnull request, GCDWebServerCompletionBlock  _Nonnull completionBlock) {
//        BOOL forceRefresh = [[request.query objectForKey:@"forceRefresh"] boolValue];
//        
//        // UI operations must be on the main thread
//        dispatch_async(dispatch_get_main_queue(), ^{
//            NSDictionary *tree = [RNUiInspector buildUiTreeForceRefresh:forceRefresh];
//            if (tree) {
//                NSError *error = nil;
//                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"status":@"success", @"data":tree} options:0 error:&error];
//                if (error) {
//                    completionBlock([GCDWebServerDataResponse responseWithData:[NSData data] contentType:@"application/json"]);
//                } else {
//                    completionBlock([GCDWebServerDataResponse responseWithData:jsonData contentType:@"application/json"]);
//                }
//            } else {
//                NSError *error = nil;
//                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"status":@"error", @"message":@"Failed to build UI tree."} options:0 error:&error];
//                if (error) {
//                    completionBlock([GCDWebServerDataResponse responseWithData:[NSData data] contentType:@"application/json"]);
//                } else {
//                    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithData:jsonData contentType:@"application/json"];
//                    [response setStatusCode:500];
//                    completionBlock(response);
//                }
//            }
//        });
//    }];
//
//    // Handler for /query
//    [self.gcdWebServer addHandlerForMethod:@"GET" // Or POST if query becomes complex
//                                      path:@"/query"
//                              requestClass:[GCDWebServerRequest class] // Use GCDWebServerDataRequest for POST JSON
//                         asyncProcessBlock:^(__kindof GCDWebServerRequest * _Nonnull request, GCDWebServerCompletionBlock  _Nonnull completionBlock) {
//        
//        NSMutableDictionary<NSString *, NSString *> *criteria = [NSMutableDictionary dictionary];
//        // Basic GET query param parsing
//        if ([request.query objectForKey:@"testID"]) {
//            criteria[@"testID"] = [request.query objectForKey:@"testID"];
//        }
//        if ([request.query objectForKey:@"accessibilityLabel"]) {
//            criteria[@"accessibilityLabel"] = [request.query objectForKey:@"accessibilityLabel"];
//        }
//        if ([request.query objectForKey:@"type"]) {
//            criteria[@"type"] = [request.query objectForKey:@"type"];
//        }
//        // Note: customXPath parsing would be more complex and is omitted for this PoC's GET version.
//        // For a simplified "customXPath" like //TYPE[@ATTR='VALUE'], you'd parse it here.
//
//        BOOL forceRefresh = [[request.query objectForKey:@"forceRefresh"] boolValue];
//
//        dispatch_async(dispatch_get_main_queue(), ^{
//            NSDictionary *tree = [RNUiInspector buildUiTreeForceRefresh:forceRefresh];
//            if (!tree) {
//                NSError *error = nil;
//                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"status":@"error", @"message":@"UI Tree not available for query."} options:0 error:&error];
//                if (error) {
//                    completionBlock([GCDWebServerDataResponse responseWithData:[NSData data] contentType:@"application/json"]);
//                } else {
//                    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithData:jsonData contentType:@"application/json"];
//                    [response setStatusCode:500];
//                    completionBlock(response);
//                }
//                return;
//            }
//            if (criteria.count == 0) {
//                NSError *error = nil;
//                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"status":@"error", @"message":@"No query criteria provided."} options:0 error:&error];
//                if (error) {
//                    completionBlock([GCDWebServerDataResponse responseWithData:[NSData data] contentType:@"application/json"]);
//                } else {
//                    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithData:jsonData contentType:@"application/json"];
//                    [response setStatusCode:400];
//                    completionBlock(response);
//                }
//                return;
//            }
//
//            NSArray<NSDictionary *> *foundElements = [RNUiInspector findElementsInNode:tree withCriteria:criteria];
//            if (foundElements) { // findElementsInNode returns empty array if none found, not nil
//                NSError *error = nil;
//                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"status":@"success", @"data":foundElements} options:0 error:&error];
//                if (error) {
//                    completionBlock([GCDWebServerDataResponse responseWithData:[NSData data] contentType:@"application/json"]);
//                } else {
//                    completionBlock([GCDWebServerDataResponse responseWithData:jsonData contentType:@"application/json"]);
//                }
//            } else {
//                // This case should ideally not be hit if findElementsInNode always returns an array
//                NSError *error = nil;
//                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"status":@"error", @"message":@"Error during query execution."} options:0 error:&error];
//                if (error) {
//                    completionBlock([GCDWebServerDataResponse responseWithData:[NSData data] contentType:@"application/json"]);
//                } else {
//                    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithData:jsonData contentType:@"application/json"];
//                    [response setStatusCode:500];
//                    completionBlock(response);
//                }
//            }
//        });
//    }];
//    
//    // Handler for /action
//    [self.gcdWebServer addHandlerForMethod:@"POST"
//                                      path:@"/action"
//                              requestClass:[GCDWebServerDataRequest class] // Expect JSON body
//                         asyncProcessBlock:^(__kindof GCDWebServerDataRequest * _Nonnull request, GCDWebServerCompletionBlock  _Nonnull completionBlock) {
//        
//        GCDWebServerDataRequest *dataRequest = (GCDWebServerDataRequest*)request;
//        NSDictionary *jsonBody = dataRequest.jsonObject;
//
//        NSString *nativeHandle = jsonBody[@"nativeHandle"];
//        NSString *actionName = jsonBody[@"action"];
//        NSDictionary *parameters = jsonBody[@"parameters"];
//
//        if (!nativeHandle || !actionName) {
//            NSError *error = nil;
//            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"status":@"error", @"message":@"'nativeHandle' and 'action' are required in JSON body."} options:0 error:&error];
//            if (error) {
//                completionBlock([GCDWebServerDataResponse responseWithData:[NSData data] contentType:@"application/json"]);
//            } else {
//                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithData:jsonData contentType:@"application/json"];
//                [response setStatusCode:400];
//                completionBlock(response);
//            }
//            return;
//        }
//        
//        // Perform action on main thread as it involves UI
//        dispatch_async(dispatch_get_main_queue(), ^{
//            NSDictionary *actionResult = [RNUiInspector performNativeAction:actionName
//                                                                 onElementPath:nativeHandle
//                                                                withParameters:parameters];
//            // performNativeAction already wraps its result in status/data or status/message
//            NSError *error = nil;
//            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:actionResult options:0 error:&error];
//            if (error) {
//                completionBlock([GCDWebServerDataResponse responseWithData:[NSData data] contentType:@"application/json"]);
//                return;
//            }
//            
//            GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithData:jsonData contentType:@"application/json"];
//            if (![actionResult[@"status"] isEqualToString:@"success"]) {
//                [response setStatusCode:500]; // Or 404 if element not found by handle
//            }
//            completionBlock(response);
//        });
//    }];
//    
//    // Handler for /elementMetadata (get fresh metadata for a single element)
//    [self.gcdWebServer addHandlerForMethod:@"GET"
//                                      path:@"/elementMetadata"
//                              requestClass:[GCDWebServerRequest class]
//                         asyncProcessBlock:^(__kindof GCDWebServerRequest * _Nonnull request, GCDWebServerCompletionBlock  _Nonnull completionBlock) {
//        NSString *nativeHandle = [request.query objectForKey:@"nativeHandle"];
//        if (!nativeHandle) {
//            NSError *error = nil;
//            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"status":@"error", @"message":@"'nativeHandle' query parameter is required."} options:0 error:&error];
//            if (error) {
//                completionBlock([GCDWebServerDataResponse responseWithData:[NSData data] contentType:@"application/json"]);
//            } else {
//                GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithData:jsonData contentType:@"application/json"];
//                [response setStatusCode:400];
//                completionBlock(response);
//            }
//            return;
//        }
//        dispatch_async(dispatch_get_main_queue(), ^{
//            NSDictionary *metadata = [RNUiInspector getElementMetadataByPath:nativeHandle];
//            if (metadata) {
//                NSError *error = nil;
//                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"status":@"success", @"data":metadata} options:0 error:&error];
//                if (error) {
//                    completionBlock([GCDWebServerDataResponse responseWithData:[NSData data] contentType:@"application/json"]);
//                } else {
//                    completionBlock([GCDWebServerDataResponse responseWithData:jsonData contentType:@"application/json"]);
//                }
//            } else {
//                NSError *error = nil;
//                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"status":@"error", @"message":@"Element not found or failed to get metadata."} options:0 error:&error];
//                if (error) {
//                    completionBlock([GCDWebServerDataResponse responseWithData:[NSData data] contentType:@"application/json"]);
//                } else {
//                    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithData:jsonData contentType:@"application/json"];
//                    [response setStatusCode:404];
//                    completionBlock(response);
//                }
//            }
//        });
//    }];
//
//
//    // Default handler for CORS preflight OPTIONS requests
//    [self.gcdWebServer addDefaultHandlerForMethod:@"OPTIONS"
//                                     requestClass:[GCDWebServerRequest class]
//                                     processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
//        GCDWebServerResponse* response = [GCDWebServerResponse response];
//        [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];
//        [response setValue:@"GET, POST, OPTIONS" forAdditionalHeader:@"Access-Control-Allow-Methods"];
//        [response setValue:@"Content-Type, Authorization" forAdditionalHeader:@"Access-Control-Allow-Headers"];
//        return response;
//    }];
//}
//
//- (void)startServer {
//    if (self.gcdWebServer.isRunning) {
//        NSLog(LOG_PREFIX @"Server is already running on port %lu", (unsigned long)self.gcdWebServer.port);
//        return;
//    }
//    
//    NSDictionary *options = @{
//        GCDWebServerOption_Port: @(SERVER_PORT),
//        GCDWebServerOption_BindToLocalhost: @(YES) // For simulator. For device, use device IP or 0.0.0.0 (careful with firewall)
//        // GCDWebServerOption_BonjourName: @"MyInspectorService" // Optional: for Bonjour discovery
//    };
//
//    NSError *error = nil;
//    if ([self.gcdWebServer startWithOptions:options error:&error]) {
//        NSLog(LOG_PREFIX @"Server started successfully on port %lu. Access via http://localhost:%lu", (unsigned long)self.gcdWebServer.port, (unsigned long)self.gcdWebServer.port);
//    } else {
//        NSLog(LOG_PREFIX @"Error starting server: %@", error.localizedDescription);
//        if (error.code == EADDRINUSE) {
//             NSLog(LOG_PREFIX @"Port %lu is already in use. Check for other running instances or services.", (unsigned long)SERVER_PORT);
//        }
//    }
//}
//
//- (void)stopServer {
//    if (self.gcdWebServer.isRunning) {
//        [self.gcdWebServer stop];
//        NSLog(LOG_PREFIX @"Server stopped.");
//    }
//}
//
//@end
