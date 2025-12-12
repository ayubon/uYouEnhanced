/**
 * DeArrowClient.h
 * DeArrow API client for fetching community-sourced titles and thumbnails
 * Part of uYouEnhanced - DeArrow Integration
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * DeArrowResult - contains fetched title and thumbnail data
 */
@interface DeArrowResult : NSObject

@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSURL *thumbnailURL;
@property (nonatomic, copy, nullable) NSNumber *thumbnailTimestamp; // Video timestamp for thumbnail
@property (nonatomic, assign) BOOL hasTitle;
@property (nonatomic, assign) BOOL hasThumbnail;
@property (nonatomic, assign) BOOL locked; // Whether title is locked by submitter
@property (nonatomic, copy, nullable) NSString *videoId;

+ (instancetype)emptyResultForVideoId:(NSString *)videoId;

@end

/**
 * DeArrowClient - Singleton client for DeArrow API
 */
@interface DeArrowClient : NSObject

/**
 * Get shared instance
 */
+ (instancetype)sharedInstance;

/**
 * Fetch DeArrow metadata for a video
 * @param videoId YouTube video ID
 * @param completion Callback with result (always called on main thread)
 */
- (void)fetchMetadataForVideoId:(NSString *)videoId
                     completion:(void (^)(DeArrowResult * _Nullable result, NSError * _Nullable error))completion;

/**
 * Fetch DeArrow metadata with priority (for visible cells)
 * @param videoId YouTube video ID
 * @param highPriority If YES, fetches immediately; if NO, may be batched
 * @param completion Callback with result (always called on main thread)
 */
- (void)fetchMetadataForVideoId:(NSString *)videoId
                   highPriority:(BOOL)highPriority
                     completion:(void (^)(DeArrowResult * _Nullable result, NSError * _Nullable error))completion;

/**
 * Get cached result if available (synchronous)
 * @param videoId YouTube video ID
 * @return Cached result or nil if not cached
 */
- (DeArrowResult * _Nullable)cachedResultForVideoId:(NSString *)videoId;

/**
 * Clear all cached data
 */
- (void)clearCache;

/**
 * Set custom API instance URL (default: https://sponsor.ajay.app)
 */
@property (nonatomic, copy) NSString *apiBaseURL;

@end

NS_ASSUME_NONNULL_END

