/**
 * DeArrowPreferences.h
 * Preference helpers for DeArrow integration
 * Part of uYouEnhanced - DeArrow Integration
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Preference Keys
extern NSString * const kDeArrowEnabled;
extern NSString * const kDeArrowTitlesEnabled;
extern NSString * const kDeArrowThumbnailsEnabled;
extern NSString * const kDeArrowReplaceInFeed;
extern NSString * const kDeArrowReplaceInWatch;
extern NSString * const kDeArrowShowOriginalOnLongPress;
extern NSString * const kDeArrowAPIInstance;

@interface DeArrowPreferences : NSObject

/**
 * Check if DeArrow is globally enabled
 */
+ (BOOL)isEnabled;

/**
 * Check if DeArrow titles replacement is enabled
 */
+ (BOOL)titlesEnabled;

/**
 * Check if DeArrow thumbnails replacement is enabled
 */
+ (BOOL)thumbnailsEnabled;

/**
 * Check if replacement should happen in feed (home, search, etc.)
 */
+ (BOOL)replaceInFeed;

/**
 * Check if replacement should happen on watch page
 */
+ (BOOL)replaceInWatch;

/**
 * Check if long press should show original title
 */
+ (BOOL)showOriginalOnLongPress;

/**
 * Get custom API instance URL
 */
+ (NSString *)apiInstance;

/**
 * Reload preferences from storage
 */
+ (void)reloadPreferences;

@end

NS_ASSUME_NONNULL_END

