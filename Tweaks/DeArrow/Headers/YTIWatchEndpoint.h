/**
 * YTIWatchEndpoint+DeArrow.h
 * Category to declare properties missing from YouTubeHeader
 * These properties exist at runtime but aren't in the headers
 */

#import "../../YouTubeHeader/YTIWatchEndpoint.h"

@interface YTIWatchEndpoint (DeArrow)
// These properties exist at runtime, just not declared in headers
@property (nonatomic, copy, readwrite) NSString *videoId;
@property (nonatomic, copy, readwrite) NSString *playlistId;
@property (nonatomic, assign, readwrite) int32_t index;
@end

