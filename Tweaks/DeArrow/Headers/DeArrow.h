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

// DeArrow headers
#import "DeArrowClient.h"
#import "DeArrowPreferences.h"

// Rootless support
#import <rootless.h>

// Bundle helper
extern NSBundle *DeArrowBundle(void);

// Logging macros
#ifdef DEBUG
#define DALog(fmt, ...) NSLog(@"[DeArrow] " fmt, ##__VA_ARGS__)
#else
#define DALog(fmt, ...)
#endif

// Associated object keys for storing original values
extern const void *kDeArrowOriginalTitleKey;
extern const void *kDeArrowModifiedKey;
extern const void *kDeArrowVideoIdKey;

