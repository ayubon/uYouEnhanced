/**
 * DeArrowPreferences.m
 * Preference storage and retrieval for DeArrow
 * Part of uYouEnhanced - DeArrow Integration
 */

#import "Headers/DeArrowPreferences.h"

// Preference Keys
NSString * const kDeArrowEnabled = @"deArrow_enabled";
NSString * const kDeArrowTitlesEnabled = @"deArrowTitles_enabled";
NSString * const kDeArrowThumbnailsEnabled = @"deArrowThumbnails_enabled";
NSString * const kDeArrowReplaceInFeed = @"deArrowReplaceInFeed_enabled";
NSString * const kDeArrowReplaceInWatch = @"deArrowReplaceInWatch_enabled";
NSString * const kDeArrowShowOriginalOnLongPress = @"deArrowShowOriginalOnLongPress_enabled";
NSString * const kDeArrowAPIInstance = @"deArrowAPIInstance";

// Default API instance
static NSString * const kDefaultAPIInstance = @"https://sponsor.ajay.app";

// Cached values
static BOOL _isEnabled = YES;
static BOOL _titlesEnabled = YES;
static BOOL _thumbnailsEnabled = YES;
static BOOL _replaceInFeed = YES;
static BOOL _replaceInWatch = YES;
static BOOL _showOriginalOnLongPress = YES;
static NSString *_apiInstance = nil;

@implementation DeArrowPreferences

+ (void)initialize {
    if (self == [DeArrowPreferences class]) {
        [self reloadPreferences];
    }
}

+ (void)reloadPreferences {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // If key doesn't exist, use default value (enabled by default)
    if ([defaults objectForKey:kDeArrowEnabled] == nil) {
        _isEnabled = YES;
    } else {
        _isEnabled = [defaults boolForKey:kDeArrowEnabled];
    }
    
    if ([defaults objectForKey:kDeArrowTitlesEnabled] == nil) {
        _titlesEnabled = YES;
    } else {
        _titlesEnabled = [defaults boolForKey:kDeArrowTitlesEnabled];
    }
    
    if ([defaults objectForKey:kDeArrowThumbnailsEnabled] == nil) {
        _thumbnailsEnabled = YES;
    } else {
        _thumbnailsEnabled = [defaults boolForKey:kDeArrowThumbnailsEnabled];
    }
    
    if ([defaults objectForKey:kDeArrowReplaceInFeed] == nil) {
        _replaceInFeed = YES;
    } else {
        _replaceInFeed = [defaults boolForKey:kDeArrowReplaceInFeed];
    }
    
    if ([defaults objectForKey:kDeArrowReplaceInWatch] == nil) {
        _replaceInWatch = YES;
    } else {
        _replaceInWatch = [defaults boolForKey:kDeArrowReplaceInWatch];
    }
    
    if ([defaults objectForKey:kDeArrowShowOriginalOnLongPress] == nil) {
        _showOriginalOnLongPress = YES;
    } else {
        _showOriginalOnLongPress = [defaults boolForKey:kDeArrowShowOriginalOnLongPress];
    }
    
    NSString *customAPI = [defaults stringForKey:kDeArrowAPIInstance];
    if (customAPI.length > 0) {
        _apiInstance = customAPI;
    } else {
        _apiInstance = kDefaultAPIInstance;
    }
}

+ (BOOL)isEnabled {
    return _isEnabled;
}

+ (BOOL)titlesEnabled {
    return _isEnabled && _titlesEnabled;
}

+ (BOOL)thumbnailsEnabled {
    return _isEnabled && _thumbnailsEnabled;
}

+ (BOOL)replaceInFeed {
    return _isEnabled && _replaceInFeed;
}

+ (BOOL)replaceInWatch {
    return _isEnabled && _replaceInWatch;
}

+ (BOOL)showOriginalOnLongPress {
    return _showOriginalOnLongPress;
}

+ (NSString *)apiInstance {
    return _apiInstance ?: kDefaultAPIInstance;
}

@end

