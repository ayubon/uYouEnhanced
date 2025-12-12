/**
 * DeArrow.h
 * Main header file for DeArrow tweak
 * Part of uYouEnhanced - DeArrow Integration
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Include YouTube headers
#import "../../YouTubeHeader/YTPlayerViewController.h"
#import "../../YouTubeHeader/YTSingleVideo.h"
#import "../../YouTubeHeader/YTIVideoDetails.h"
#import "../../YouTubeHeader/YTPlayerView.h"
#import "../../YouTubeHeader/YTMainAppVideoPlayerOverlayView.h"
#import "../../YouTubeHeader/YTMainAppControlsOverlayView.h"
#import "../../YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h"
#import "../../YouTubeHeader/YTSingleVideoController.h"
#import "../../YouTubeHeader/YTPlaybackData.h"
#import "../../YouTubeHeader/MLVideo.h"
#import "../../YouTubeHeader/YTInnerTubeCollectionViewController.h"
#import "../../YouTubeHeader/YTWatchViewController.h"
#import "../../YouTubeHeader/_ASDisplayView.h"
#import "../../YouTubeHeader/ASDisplayNode.h"
// Local header with videoId property (not in upstream YouTubeHeader)
#import "YTIWatchEndpoint.h"
#import "../../YouTubeHeader/YTICommand.h"
#import "../../YouTubeHeader/YTInnerTubeSectionController.h"

// DeArrow headers
#import "DeArrowClient.h"
#import "DeArrowPreferences.h"

// Rootless support
#import <rootless.h>

// Bundle helper
extern NSBundle *DeArrowBundle(void);

// Logging macros - Always enabled for debugging
// Use %{public}@ to avoid iOS privacy filtering in Console.app
#define DALog(fmt, ...) NSLog(@"[DeArrow] " fmt, ##__VA_ARGS__)
#define DALogPublic(fmt, ...) os_log(OS_LOG_DEFAULT, "[DeArrow] " fmt, ##__VA_ARGS__)

// Associated object keys for storing original values
extern const void *kDeArrowOriginalTitleKey;
extern const void *kDeArrowModifiedKey;
extern const void *kDeArrowVideoIdKey;

// Interface extensions for hooked classes to declare %new methods and properties
// These help the compiler understand the methods added by Logos %new

@interface YTPlayerViewController (DeArrow)
@property (nonatomic, copy) NSString *deArrowOriginalTitle;
@property (nonatomic, copy) NSString *deArrowCurrentVideoId;
- (void)da_applyDeArrowTitle:(NSString *)newTitle;
@end

@class DeArrowResult;

@interface YTInnerTubeCollectionViewController (DeArrow)
- (NSString *)da_extractVideoIdFromCell:(UICollectionViewCell *)cell;
- (void)da_applyDeArrowResult:(DeArrowResult *)result toCell:(UICollectionViewCell *)cell;
- (void)da_updateTitleInCell:(UICollectionViewCell *)cell withTitle:(NSString *)newTitle;
- (BOOL)da_findAndUpdateLabelInView:(UIView *)view withTitle:(NSString *)newTitle;
- (void)da_updateThumbnailInCell:(UICollectionViewCell *)cell withURL:(NSURL *)thumbnailURL;
- (BOOL)da_findAndUpdateThumbnailInView:(UIView *)view withURL:(NSURL *)thumbnailURL;
@end

@interface _ASDisplayView (DeArrow)
- (void)da_checkAndApplyDeArrow;
@end

