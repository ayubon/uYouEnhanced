/**
 * Tweak.xm
 * DeArrow integration for YouTube - replaces clickbait titles and thumbnails
 * Part of uYouEnhanced
 * 
 * DeArrow is a browser extension for crowdsourced YouTube titles and thumbnails.
 * This tweak brings DeArrow functionality to the iOS YouTube app.
 * 
 * Hooks target:
 * 1. Video feed cells (home, subscriptions, search, related videos)
 * 2. Watch page (video title)
 * 3. Thumbnails throughout the app
 */

#import "Headers/DeArrow.h"
#import <objc/runtime.h>

// Associated object keys
const void *kDeArrowOriginalTitleKey = &kDeArrowOriginalTitleKey;
const void *kDeArrowModifiedKey = &kDeArrowModifiedKey;
const void *kDeArrowVideoIdKey = &kDeArrowVideoIdKey;

// Bundle helper
NSBundle *DeArrowBundle(void) {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"DeArrow" ofType:@"bundle"];
        bundle = [NSBundle bundleWithPath:(tweakBundlePath ?: ROOT_PATH_NS(@"/Library/Application Support/DeArrow.bundle"))];
    });
    return bundle;
}

#pragma mark - Helper Functions

/**
 * Extract video ID from various YouTube objects
 */
static NSString *extractVideoId(id object) {
    if (!object) return nil;
    
    // Try common patterns
    if ([object respondsToSelector:@selector(videoId)]) {
        return [object videoId];
    }
    
    if ([object respondsToSelector:@selector(video)]) {
        id video = [object video];
        if ([video respondsToSelector:@selector(videoId)]) {
            return [video videoId];
        }
    }
    
    if ([object respondsToSelector:@selector(playbackData)]) {
        id playbackData = [object playbackData];
        if ([playbackData respondsToSelector:@selector(video)]) {
            id video = [playbackData video];
            if ([video respondsToSelector:@selector(videoId)]) {
                return [video videoId];
            }
        }
    }
    
    // Try accessing via key-value coding
    @try {
        NSString *videoId = [object valueForKey:@"videoId"];
        if ([videoId isKindOfClass:[NSString class]]) {
            return videoId;
        }
    } @catch (NSException *e) {}
    
    return nil;
}

#pragma mark - Main Hooks Group

%group DeArrowMain

/**
 * Hook: YTPlayerViewController
 * Purpose: Replace title on watch/player page
 * 
 * This class controls the video player and has access to the current video info.
 * We hook into the video loading/activation methods to fetch and apply DeArrow data.
 */
%hook YTPlayerViewController

// Store original title for this instance
%property (nonatomic, copy) NSString *deArrowOriginalTitle;
%property (nonatomic, copy) NSString *deArrowCurrentVideoId;

- (void)playbackController:(id)controller didActivateVideo:(id)video withPlaybackData:(id)playbackData {
    %orig;
    
    DALog(@"🎬 playbackController:didActivateVideo: called!");
    
    if (![DeArrowPreferences isEnabled] || ![DeArrowPreferences replaceInWatch]) {
        DALog(@"DeArrow disabled for watch, skipping");
        return;
    }
    
    // Don't process ads
    if ([self respondsToSelector:@selector(isPlayingAd)] && self.isPlayingAd) {
        return;
    }
    
    NSString *videoId = nil;
    
    // Try to get videoId from activeVideo.singleVideo
    if ([self respondsToSelector:@selector(activeVideo)]) {
        id activeVideo = self.activeVideo;
        if ([activeVideo respondsToSelector:@selector(singleVideo)]) {
            id singleVideo = [activeVideo singleVideo];
            videoId = extractVideoId(singleVideo);
        }
    }
    
    // Fallback: try currentVideoID property
    if (!videoId && [self respondsToSelector:@selector(currentVideoID)]) {
        videoId = self.currentVideoID;
    }
    
    if (!videoId) {
        DALog(@"Could not extract videoId from player");
        return;
    }
    
    self.deArrowCurrentVideoId = videoId;
    NSLog(@"[DeArrow] Player activated video: %s", [videoId UTF8String]);
    
    // Fetch DeArrow data
    [[DeArrowClient sharedInstance] fetchMetadataForVideoId:videoId highPriority:YES completion:^(DeArrowResult *result, NSError *error) {
        if (error || !result || !result.hasTitle) {
            NSLog(@"[DeArrow] No DeArrow title for %s: %s", [videoId UTF8String], [error.localizedDescription UTF8String]);
            return;
        }
        
        // Verify we're still on the same video
        if (![self.deArrowCurrentVideoId isEqualToString:videoId]) {
            return;
        }
        
        DALog(@"Applying DeArrow title: %@", result.title);
        [self da_applyDeArrowTitle:result.title];
    }];
}

%new
- (void)da_applyDeArrowTitle:(NSString *)newTitle {
    if (!newTitle.length) return;
    
    // Try to find and update title label in player overlay
    if ([self respondsToSelector:@selector(view)]) {
        UIView *playerView = self.view;
        if ([playerView isKindOfClass:%c(YTPlayerView)]) {
            YTMainAppVideoPlayerOverlayView *overlayView = (YTMainAppVideoPlayerOverlayView *)[(YTPlayerView *)playerView overlayView];
            if ([overlayView isKindOfClass:%c(YTMainAppVideoPlayerOverlayView)]) {
                // Find title label in controls overlay
                YTMainAppControlsOverlayView *controlsOverlay = overlayView.controlsOverlayView;
                if (controlsOverlay) {
                    // Try to access videoTitle property or find label
                    @try {
                        id titleView = [controlsOverlay valueForKey:@"_videoTitle"];
                        if ([titleView respondsToSelector:@selector(setText:)]) {
                            // Store original
                            NSString *original = [titleView respondsToSelector:@selector(text)] ? [titleView text] : nil;
                            if (original && !self.deArrowOriginalTitle) {
                                self.deArrowOriginalTitle = original;
                            }
                            [titleView setText:newTitle];
                            DALog(@"Updated title via _videoTitle");
                        }
                    } @catch (NSException *e) {
                        DALog(@"Exception accessing _videoTitle: %@", e);
                    }
                }
            }
        }
    }
}

%end

/**
 * Hook: YTInnerTubeCollectionViewController
 * Purpose: Process video renderers in feed sections
 * 
 * This handles home feed, subscriptions, search results, etc.
 */
%hook YTInnerTubeCollectionViewController

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    %orig;
    
    DALog(@"📱 collectionView:willDisplayCell: called at indexPath %@", indexPath);
    
    if (![DeArrowPreferences isEnabled] || ![DeArrowPreferences replaceInFeed]) {
        DALog(@"DeArrow disabled for feed, skipping");
        return;
    }
    
    // Find video ID from cell
    NSString *videoId = [self da_extractVideoIdFromCell:cell];
    if (!videoId) return;
    
    // Check cache first for instant update
    DeArrowResult *cached = [[DeArrowClient sharedInstance] cachedResultForVideoId:videoId];
    if (cached && cached.hasTitle && [DeArrowPreferences titlesEnabled]) {
        [self da_applyDeArrowResult:cached toCell:cell];
        return;
    }
    
    // Fetch from API
    [[DeArrowClient sharedInstance] fetchMetadataForVideoId:videoId completion:^(DeArrowResult *result, NSError *error) {
        if (error || !result) return;
        
        // Cell might have been recycled - verify
        NSString *currentVideoId = [self da_extractVideoIdFromCell:cell];
        if (![currentVideoId isEqualToString:videoId]) return;
        
        [self da_applyDeArrowResult:result toCell:cell];
    }];
}

%new
- (NSString *)da_extractVideoIdFromCell:(UICollectionViewCell *)cell {
    NSString *cellClass = NSStringFromClass([cell class]);
    
    // Skip non-video cells
    if ([cellClass containsString:@"Drawer"] ||
        [cellClass containsString:@"Link"] ||
        [cellClass containsString:@"Chip"] ||
        [cellClass containsString:@"Header"] ||
        [cellClass containsString:@"Avatar"] ||
        [cellClass containsString:@"Separator"]) {
        return nil; // Not a video cell
    }
    
    DALog(@"🔍 Processing cell class: %@", cellClass);
    
    @try {
        // Try to get controller for this cell
        id controller = nil;
        
        // Try different controller key paths
        NSArray *controllerKeys = @[@"_nodeController", @"_controller", @"_cellController", @"controller"];
        for (NSString *key in controllerKeys) {
            @try {
                controller = [cell valueForKey:key];
                if (controller) {
                    DALog(@"  Found controller via key: %@", key);
                    break;
                }
            } @catch (NSException *e) {
                // Key doesn't exist, try next
            }
        }
        
        if (controller) {
            NSString *controllerClass = NSStringFromClass([controller class]);
            DALog(@"  Controller class: %@", controllerClass);
            
            // Try multiple paths to get videoId
            NSString *videoId = extractVideoId(controller);
            if (videoId) {
                DALog(@"  ✅ Found videoId from controller: %@", videoId);
                return videoId;
            }
            
            // Try model/renderer
            id model = nil;
            if ([controller respondsToSelector:@selector(model)]) {
                model = [controller model];
                DALog(@"  Found model: %@", NSStringFromClass([model class]));
            } else if ([controller respondsToSelector:@selector(renderer)]) {
                model = [(YTInnerTubeSectionController *)controller renderer];
                DALog(@"  Found renderer: %@", NSStringFromClass([model class]));
            }
            
            if (model) {
                videoId = extractVideoId(model);
                if (videoId) {
                    DALog(@"  ✅ Found videoId from model: %@", videoId);
                    return videoId;
                }
            }
        }
        
        // Try accessibilityIdentifier as fallback (some cells encode videoId there)
        NSString *accessId = cell.accessibilityIdentifier;
        if (accessId.length == 11) { // YouTube video IDs are 11 characters
            DALog(@"  ✅ Found videoId from accessibilityIdentifier: %@", accessId);
            return accessId;
        }
        
        // Try to find videoId in cell's view hierarchy description
        DALog(@"  ❌ Could not extract videoId from cell");
        
    } @catch (NSException *e) {
        DALog(@"Exception extracting videoId from %@: %@", cellClass, e);
    }
    
    return nil;
}

%new
- (void)da_applyDeArrowResult:(DeArrowResult *)result toCell:(UICollectionViewCell *)cell {
    if (!result) return;
    
    // Apply title
    if (result.hasTitle && [DeArrowPreferences titlesEnabled]) {
        [self da_updateTitleInCell:cell withTitle:result.title];
    }
    
    // Apply thumbnail (if enabled)
    if (result.hasThumbnail && result.thumbnailURL && [DeArrowPreferences thumbnailsEnabled]) {
        [self da_updateThumbnailInCell:cell withURL:result.thumbnailURL];
    }
}

%new
- (void)da_updateTitleInCell:(UICollectionViewCell *)cell withTitle:(NSString *)newTitle {
    if (!newTitle.length) return;
    
    // Recursively find label views
    [self da_findAndUpdateLabelInView:cell withTitle:newTitle];
}

%new
- (BOOL)da_findAndUpdateLabelInView:(UIView *)view withTitle:(NSString *)newTitle {
    // Check if this view is the title label
    // Title labels typically have certain characteristics
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        
        // Check if this looks like a video title label
        // Title labels are usually multi-line and have certain styling
        if (label.numberOfLines != 1 || label.text.length > 20) {
            NSString *currentText = label.text;
            
            // Skip if already modified with this title
            if ([currentText isEqualToString:newTitle]) {
                return YES;
            }
            
            // Skip channel names, view counts, timestamps
            if ([currentText containsString:@" views"] ||
                [currentText containsString:@" subscribers"] ||
                [currentText containsString:@"ago"] ||
                currentText.length < 10) {
                return NO;
            }
            
            // Store original title
            NSString *stored = objc_getAssociatedObject(label, kDeArrowOriginalTitleKey);
            if (!stored) {
                objc_setAssociatedObject(label, kDeArrowOriginalTitleKey, currentText, OBJC_ASSOCIATION_COPY_NONATOMIC);
            }
            
            // Update title
            label.text = newTitle;
            objc_setAssociatedObject(label, kDeArrowModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            
            DALog(@"Updated cell title: %@ -> %@", currentText, newTitle);
            return YES;
        }
    }
    
    // Recurse into subviews
    for (UIView *subview in view.subviews) {
        if ([self da_findAndUpdateLabelInView:subview withTitle:newTitle]) {
            return YES;
        }
    }
    
    return NO;
}

%new
- (void)da_updateThumbnailInCell:(UICollectionViewCell *)cell withURL:(NSURL *)thumbnailURL {
    if (!thumbnailURL) return;
    
    // Find UIImageView for thumbnail
    [self da_findAndUpdateThumbnailInView:cell withURL:thumbnailURL];
}

%new
- (BOOL)da_findAndUpdateThumbnailInView:(UIView *)view withURL:(NSURL *)thumbnailURL {
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)view;
        
        // Check if this looks like a video thumbnail (16:9 aspect ratio, larger size)
        CGFloat aspectRatio = imageView.frame.size.width / imageView.frame.size.height;
        if (aspectRatio > 1.5 && aspectRatio < 2.0 && imageView.frame.size.width > 100) {
            
            // Check if already modified
            if (objc_getAssociatedObject(imageView, kDeArrowModifiedKey)) {
                return YES;
            }
            
            // Load new thumbnail asynchronously
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *imageData = [NSData dataWithContentsOfURL:thumbnailURL];
                if (imageData) {
                    UIImage *newImage = [UIImage imageWithData:imageData];
                    if (newImage) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            // Store original
                            if (!objc_getAssociatedObject(imageView, kDeArrowOriginalTitleKey)) {
                                objc_setAssociatedObject(imageView, kDeArrowOriginalTitleKey, imageView.image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                            }
                            imageView.image = newImage;
                            objc_setAssociatedObject(imageView, kDeArrowModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                            DALog(@"Updated thumbnail image");
                        });
                    }
                }
            });
            
            return YES;
        }
    }
    
    // Recurse
    for (UIView *subview in view.subviews) {
        if ([self da_findAndUpdateThumbnailInView:subview withURL:thumbnailURL]) {
            return YES;
        }
    }
    
    return NO;
}

%end

/**
 * Hook: ELMTextNode (Element-based text rendering)
 * Purpose: Intercept title rendering in modern YouTube UI
 * 
 * Newer YouTube versions use ELM (Element) framework for rendering.
 * This provides a lower-level hook point.
 */
%hook _ASDisplayView

- (void)didMoveToWindow {
    %orig;
    
    if (![DeArrowPreferences isEnabled]) return;
    
    // Check if this might be a video title element
    NSString *accessId = self.accessibilityIdentifier;
    if ([accessId containsString:@"video_title"] || [accessId containsString:@"metadata"]) {
        // Try to find associated video ID and apply DeArrow
        [self da_checkAndApplyDeArrow];
    }
}

%new
- (void)da_checkAndApplyDeArrow {
    // Find video ID from parent hierarchy
    NSString *videoId = nil;
    UIResponder *responder = self.nextResponder;
    
    while (responder && !videoId) {
        videoId = extractVideoId(responder);
        if (!videoId && [responder respondsToSelector:@selector(accessibilityIdentifier)]) {
            NSString *identifier = [(UIView *)responder accessibilityIdentifier];
            if (identifier.length == 11) {
                videoId = identifier;
            }
        }
        responder = responder.nextResponder;
    }
    
    if (!videoId) return;
    
    DeArrowResult *cached = [[DeArrowClient sharedInstance] cachedResultForVideoId:videoId];
    if (cached && cached.hasTitle && [DeArrowPreferences titlesEnabled]) {
        // Find and update labels in this view
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:[UILabel class]]) {
                UILabel *label = (UILabel *)subview;
                if (label.text.length > 15 && ![label.text isEqualToString:cached.title]) {
                    label.text = cached.title;
                    DALog(@"Updated ELM label: %@", cached.title);
                }
            }
        }
    }
}

%end

/**
 * Hook: YTWatchController / YTWatchViewController
 * Purpose: Handle watch page title updates
 */
%hook YTWatchViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    if (![DeArrowPreferences isEnabled] || ![DeArrowPreferences replaceInWatch]) {
        return;
    }
    
    // Get video ID from the watch endpoint
    NSString *videoId = nil;
    @try {
        YTICommand *navEndpoint = [self valueForKey:@"_navEndpoint"];
        if ([navEndpoint respondsToSelector:@selector(watchEndpoint)]) {
            YTIWatchEndpoint *watchEndpoint = navEndpoint.watchEndpoint;
            if ([watchEndpoint respondsToSelector:@selector(videoId)]) {
                videoId = watchEndpoint.videoId;
            }
        }
    } @catch (NSException *e) {}
    
    if (!videoId) return;
    
    [[DeArrowClient sharedInstance] fetchMetadataForVideoId:videoId highPriority:YES completion:^(DeArrowResult *result, NSError *error) {
        if (!result || !result.hasTitle) return;
        if (![DeArrowPreferences titlesEnabled]) return;
        
        DALog(@"Watch page: applying title %@", result.title);
        // Title will be applied via YTPlayerViewController hook
    }];
}

%end

%end // DeArrowMain group

#pragma mark - Constructor

static void loadPreferences() {
    [DeArrowPreferences reloadPreferences];
}

static void prefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadPreferences();
}

%ctor {
    DALog(@"DeArrow constructor starting...");
    
    // Register for preference changes
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)prefsChanged,
        CFSTR("com.uyouenhanced.dearrow.prefschanged"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );
    
    // Load initial preferences
    loadPreferences();
    
    DALog(@"DeArrow preferences - Enabled: %@, Titles: %@, Feed: %@, Watch: %@",
          [DeArrowPreferences isEnabled] ? @"YES" : @"NO",
          [DeArrowPreferences titlesEnabled] ? @"YES" : @"NO",
          [DeArrowPreferences replaceInFeed] ? @"YES" : @"NO",
          [DeArrowPreferences replaceInWatch] ? @"YES" : @"NO");
    
    // ALWAYS initialize hooks for now (debugging)
    %init(DeArrowMain);
    DALog(@"DeArrow hooks initialized!");
}

