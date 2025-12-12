/**
 * DeArrowClient.m
 * DeArrow API client implementation with caching
 * Part of uYouEnhanced - DeArrow Integration
 * 
 * API Documentation: https://wiki.sponsor.ajay.app/w/API_Docs/DeArrow
 */

#import "Headers/DeArrowClient.h"
#import "Headers/DeArrowPreferences.h"
#import <CommonCrypto/CommonDigest.h>

// API Constants
static NSString * const kDeArrowDefaultAPI = @"https://sponsor.ajay.app";
static NSString * const kDeArrowBrandingEndpoint = @"/api/branding";
static NSTimeInterval const kCacheExpirationInterval = 3600; // 1 hour

#pragma mark - DeArrowResult Implementation

@implementation DeArrowResult

+ (instancetype)emptyResultForVideoId:(NSString *)videoId {
    DeArrowResult *result = [[DeArrowResult alloc] init];
    result.videoId = videoId;
    result.hasTitle = NO;
    result.hasThumbnail = NO;
    return result;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<DeArrowResult: videoId=%@, title=%@, hasThumbnail=%@>",
            self.videoId, self.title ?: @"(none)", self.hasThumbnail ? @"YES" : @"NO"];
}

@end

#pragma mark - Cache Entry

@interface DeArrowCacheEntry : NSObject
@property (nonatomic, strong) DeArrowResult *result;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, assign) BOOL isEmpty; // True if API returned no data
@end

@implementation DeArrowCacheEntry
@end

#pragma mark - DeArrowClient Implementation

@interface DeArrowClient ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, DeArrowCacheEntry *> *cache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *pendingRequests;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;

@end

@implementation DeArrowClient

#pragma mark - Singleton

+ (instancetype)sharedInstance {
    static DeArrowClient *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DeArrowClient alloc] init];
    });
    return instance;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSMutableDictionary dictionary];
        _pendingRequests = [NSMutableDictionary dictionary];
        _apiBaseURL = kDeArrowDefaultAPI;
        _cacheQueue = dispatch_queue_create("com.uyouenhanced.dearrow.cache", DISPATCH_QUEUE_SERIAL);
        
        // Configure URL session with reasonable timeouts
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 10.0;
        config.timeoutIntervalForResource = 30.0;
        config.HTTPMaximumConnectionsPerHost = 4;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

#pragma mark - SHA256 Hash Helper

- (NSString *)sha256HashForVideoId:(NSString *)videoId {
    const char *cStr = [videoId UTF8String];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(cStr, (CC_LONG)strlen(cStr), hash);
    
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", hash[i]];
    }
    
    // DeArrow API uses first 4 characters of hash as prefix
    return [output substringToIndex:4];
}

#pragma mark - Public API

- (void)fetchMetadataForVideoId:(NSString *)videoId
                     completion:(void (^)(DeArrowResult * _Nullable, NSError * _Nullable))completion {
    [self fetchMetadataForVideoId:videoId highPriority:NO completion:completion];
}

- (void)fetchMetadataForVideoId:(NSString *)videoId
                   highPriority:(BOOL)highPriority
                     completion:(void (^)(DeArrowResult * _Nullable, NSError * _Nullable))completion {
    
    if (!videoId || videoId.length == 0) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [NSError errorWithDomain:@"DeArrow" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid video ID"}]);
            });
        }
        return;
    }
    
    // Check cache first
    __block DeArrowCacheEntry *cached = nil;
    dispatch_sync(self.cacheQueue, ^{
        cached = self.cache[videoId];
    });
    
    if (cached) {
        NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:cached.timestamp];
        if (age < kCacheExpirationInterval) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(cached.result, nil);
                });
            }
            return;
        }
    }
    
    // Check if request already pending
    __block BOOL shouldFetch = NO;
    dispatch_sync(self.cacheQueue, ^{
        NSMutableArray *pending = self.pendingRequests[videoId];
        if (pending) {
            // Add to pending callbacks
            if (completion) {
                [pending addObject:[completion copy]];
            }
        } else {
            // Start new request
            self.pendingRequests[videoId] = [NSMutableArray arrayWithObject:completion ? [completion copy] : [NSNull null]];
            shouldFetch = YES;
        }
    });
    
    if (!shouldFetch) {
        return;
    }
    
    // Build request URL using hash prefix for privacy
    NSString *hashPrefix = [self sha256HashForVideoId:videoId];
    NSString *apiInstance = [DeArrowPreferences apiInstance] ?: self.apiBaseURL;
    NSString *urlString = [NSString stringWithFormat:@"%@%@/%@", apiInstance, kDeArrowBrandingEndpoint, hashPrefix];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    // Identify as uYouEnhanced per API best practices
    // See: https://wiki.sponsor.ajay.app/w/API_Docs
    [request setValue:@"uYouEnhanced-DeArrow/1.0 (iOS; https://github.com/arichornlover/uYouEnhanced)" forHTTPHeaderField:@"User-Agent"];
    
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        DeArrowResult *result = nil;
        NSError *resultError = error;
        
        if (!error && data) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200) {
                result = [self parseResponseData:data forVideoId:videoId];
            } else if (httpResponse.statusCode == 404) {
                // No data for this video - cache empty result
                result = [DeArrowResult emptyResultForVideoId:videoId];
            } else {
                resultError = [NSError errorWithDomain:@"DeArrow" 
                                                  code:httpResponse.statusCode 
                                              userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"API returned status %ld", (long)httpResponse.statusCode]}];
            }
        }
        
        // Cache result
        if (result) {
            DeArrowCacheEntry *entry = [[DeArrowCacheEntry alloc] init];
            entry.result = result;
            entry.timestamp = [NSDate date];
            entry.isEmpty = !result.hasTitle && !result.hasThumbnail;
            
            dispatch_sync(self.cacheQueue, ^{
                self.cache[videoId] = entry;
            });
        }
        
        // Call all pending completions
        __block NSArray *callbacks = nil;
        dispatch_sync(self.cacheQueue, ^{
            callbacks = [self.pendingRequests[videoId] copy];
            [self.pendingRequests removeObjectForKey:videoId];
        });
        
        dispatch_async(dispatch_get_main_queue(), ^{
            for (id callback in callbacks) {
                if (callback != [NSNull null]) {
                    void (^completionBlock)(DeArrowResult *, NSError *) = callback;
                    completionBlock(result, resultError);
                }
            }
        });
    }];
    
    [task resume];
}

- (DeArrowResult *)cachedResultForVideoId:(NSString *)videoId {
    __block DeArrowCacheEntry *cached = nil;
    dispatch_sync(self.cacheQueue, ^{
        cached = self.cache[videoId];
    });
    
    if (cached) {
        NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:cached.timestamp];
        if (age < kCacheExpirationInterval) {
            return cached.result;
        }
    }
    
    return nil;
}

- (void)clearCache {
    dispatch_sync(self.cacheQueue, ^{
        [self.cache removeAllObjects];
    });
}

#pragma mark - Response Parsing

- (DeArrowResult *)parseResponseData:(NSData *)data forVideoId:(NSString *)videoId {
    NSError *jsonError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    
    if (jsonError || ![json isKindOfClass:[NSDictionary class]]) {
        return [DeArrowResult emptyResultForVideoId:videoId];
    }
    
    NSDictionary *responseDict = (NSDictionary *)json;
    
    // The API returns data keyed by videoId since we use hash prefix
    NSDictionary *videoData = responseDict[videoId];
    if (!videoData || ![videoData isKindOfClass:[NSDictionary class]]) {
        return [DeArrowResult emptyResultForVideoId:videoId];
    }
    
    DeArrowResult *result = [[DeArrowResult alloc] init];
    result.videoId = videoId;
    
    // Parse titles array
    NSArray *titles = videoData[@"titles"];
    if ([titles isKindOfClass:[NSArray class]] && titles.count > 0) {
        // Get first title with highest votes (already sorted by API)
        NSDictionary *titleData = titles[0];
        if ([titleData isKindOfClass:[NSDictionary class]]) {
            NSString *title = titleData[@"title"];
            if ([title isKindOfClass:[NSString class]] && title.length > 0) {
                result.title = title;
                result.hasTitle = YES;
                result.locked = [titleData[@"locked"] boolValue];
            }
        }
    }
    
    // Parse thumbnails array
    NSArray *thumbnails = videoData[@"thumbnails"];
    if ([thumbnails isKindOfClass:[NSArray class]] && thumbnails.count > 0) {
        NSDictionary *thumbData = thumbnails[0];
        if ([thumbData isKindOfClass:[NSDictionary class]]) {
            // DeArrow can return either a timestamp (for original video frame) or a URL
            NSNumber *timestamp = thumbData[@"timestamp"];
            if (timestamp && [timestamp isKindOfClass:[NSNumber class]]) {
                result.thumbnailTimestamp = timestamp;
                result.hasThumbnail = YES;
                
                // Construct thumbnail URL using YouTube's thumbnail service at the specified timestamp
                // Format: https://i.ytimg.com/vi_webp/VIDEO_ID/mqdefault.webp (we'll handle timestamp client-side)
                // Or use the DeArrow thumbnail endpoint
                NSString *thumbURLString = [NSString stringWithFormat:@"%@/api/branding/thumbnail/%@?time=%@",
                                           [DeArrowPreferences apiInstance] ?: self.apiBaseURL,
                                           videoId, timestamp];
                result.thumbnailURL = [NSURL URLWithString:thumbURLString];
            }
        }
    }
    
    return result;
}

@end

