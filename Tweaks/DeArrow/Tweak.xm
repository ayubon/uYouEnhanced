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

// Static storage for current DeArrow title (for YTFormattedStringLabel hook)
static NSString *s_currentDeArrowTitle = nil;
static NSString *s_currentVideoId = nil;

static void da_setCurrentDeArrowTitle(NSString *title, NSString *videoId) {
    s_currentDeArrowTitle = [title copy];
    s_currentVideoId = [videoId copy];
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
        
        // Store the DeArrow title for YTFormattedStringLabel hook to use
        da_setCurrentDeArrowTitle(result.title, videoId);
        
        [self da_applyDeArrowTitle:result.title];
    }];
}

%new
- (void)da_applyDeArrowTitle:(NSString *)newTitle {
    if (!newTitle.length) return;
    
    DALog(@"Will apply DeArrow title for %@: %@", self.deArrowCurrentVideoId, newTitle);
    
    // Schedule repeated attempts to find and update the title
    // The metadata view may not exist immediately when video starts
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self da_attemptTitleUpdate:newTitle];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self da_attemptTitleUpdate:newTitle];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self da_attemptTitleUpdate:newTitle];
    });
}

%new
- (void)da_attemptTitleUpdate:(NSString *)newTitle {
    // Get the watch view controller's view hierarchy
    UIViewController *watchVC = nil;
    UIViewController *current = (UIViewController *)self;
    while (current) {
        if ([current isKindOfClass:%c(YTWatchViewController)] || 
            [NSStringFromClass([current class]) containsString:@"Watch"]) {
            watchVC = current;
            break;
        }
        current = current.parentViewController;
    }
    
    if (!watchVC) {
        DALog(@"Could not find watch view controller");
        return;
    }
    
    DALog(@"Found watch VC: %@, searching for title...", NSStringFromClass([watchVC class]));
    
    // Search the entire view hierarchy for title-like labels
    [self da_findTitleLabelInView:watchVC.view withNewTitle:newTitle depth:0];
}

%new
- (BOOL)da_findTitleLabelInView:(UIView *)view withNewTitle:(NSString *)newTitle depth:(int)depth {
    if (depth > 30) return NO;
    
    // FLEX-verified: Look for YTFormattedStringLabel with accessibilityIdentifier = "id.upload_metadata_editor_title_field"
    NSString *accessId = view.accessibilityIdentifier;
    
    if ([accessId isEqualToString:@"id.upload_metadata_editor_title_field"]) {
        DALog(@"🎯 Found title label by identifier! Class: %@", NSStringFromClass([view class]));
        
        // It's a YTFormattedStringLabel (subclass of UILabel)
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)view;
            NSString *oldText = label.text;
            
            if (!self.deArrowOriginalTitle) {
                self.deArrowOriginalTitle = oldText;
            }
            
            // Try to use setFormattedString: if available
            Class YTIFormattedStringClass = NSClassFromString(@"YTIFormattedString");
            if (YTIFormattedStringClass && [view respondsToSelector:@selector(setFormattedString:)]) {
                id newFormattedString = [YTIFormattedStringClass performSelector:@selector(formattedStringWithString:) withObject:newTitle];
                if (newFormattedString) {
                    [view performSelector:@selector(setFormattedString:) withObject:newFormattedString];
                    DALog(@"✅ Updated via setFormattedString: '%@' -> '%@'", oldText, newTitle);
                    return YES;
                }
            }
            
            // Fallback: direct text update
            label.text = newTitle;
            DALog(@"✅ Updated via label.text: '%@' -> '%@'", oldText, newTitle);
            return YES;
        }
    }
    
    // Recurse into subviews
    for (UIView *subview in view.subviews) {
        if ([self da_findTitleLabelInView:subview withNewTitle:newTitle depth:depth+1]) {
            return YES;
        }
    }
    
    return NO;
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
    
    if (![DeArrowPreferences isEnabled] || ![DeArrowPreferences replaceInFeed]) return;
    
    NSString *accessId = self.accessibilityIdentifier;
    
    // VERIFIED: eml.vwc is the identifier for video cells with context
    // accessibilityLabel contains: "TITLE - duration - Go to channel - CHANNEL - views - time - play video"
    if ([accessId isEqualToString:@"eml.vwc"]) {
        DALog(@"📱 Found eml.vwc cell");
        [self da_processVideoCell];
    }
}

%new
- (void)da_processVideoCell {
    NSString *label = self.accessibilityLabel;
    if (!label.length) {
        DALog(@"No accessibility label");
        return;
    }
    
    DALog(@"AccessibilityLabel: %@", [label substringToIndex:MIN(100, label.length)]);
    
    // Parse title from accessibility label
    // Format: "TITLE - duration - Go to channel - CHANNEL - views - time - play video"
    NSString *originalTitle = [self da_extractTitleFromLabel:label];
    if (!originalTitle.length) {
        DALog(@"Could not extract title");
        return;
    }
    
    DALog(@"Extracted title: %@", originalTitle);
    
    // Try to find videoId from parent hierarchy
    NSString *videoId = [self da_findVideoIdInHierarchy];
    
    if (videoId) {
        DALog(@"Found videoId: %@", videoId);
        [self da_fetchAndApplyDeArrow:videoId originalTitle:originalTitle];
    } else {
        DALog(@"Could not find videoId in hierarchy");
    }
}

%new
- (NSString *)da_extractTitleFromLabel:(NSString *)label {
    // Title is everything before " - " followed by duration pattern or "Go to channel"
    // Example: "How One Company Secretly Poisoned The Planet - 54 minutes, 8 seconds - Go to channel..."
    
    // First try to find " - " followed by duration or "Go to"
    NSArray *patterns = @[@" - \\d+ (minute|second|hour)", @" - Go to channel"];
    
    for (NSString *pattern in patterns) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:label options:0 range:NSMakeRange(0, label.length)];
        if (match) {
            NSRange titleRange = NSMakeRange(0, match.range.location);
            return [label substringWithRange:titleRange];
        }
    }
    
    // Fallback: split by " - " and take first component
    NSArray *components = [label componentsSeparatedByString:@" - "];
    if (components.count > 0) {
        return components[0];
    }
    
    return nil;
}

%new
- (NSString *)da_findVideoIdInHierarchy {
    // Walk up the view hierarchy looking for videoId
    UIResponder *responder = self;
    int depth = 0;
    
    while (responder && depth < 30) {
        // Try extractVideoId helper
        NSString *videoId = extractVideoId(responder);
        if (videoId) return videoId;
        
        // Check if this is a YTVideoWithContextNode-View or similar
        NSString *className = NSStringFromClass([responder class]);
        if ([className containsString:@"VideoWithContext"] || [className containsString:@"VideoCell"]) {
            DALog(@"Found potential video container: %@", className);
            
            // Try to get node and extract videoId
            if ([responder isKindOfClass:[UIView class]]) {
                @try {
                    id node = [(UIView *)responder valueForKey:@"asyncdisplaykit_node"];
                    if (node) {
                        videoId = extractVideoId(node);
                        if (videoId) return videoId;
                        
                        // Try element
                        id element = [node valueForKey:@"element"];
                        if (element) {
                            NSString *desc = [element description];
                            // Look for videoId pattern in description
                            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"['\"]([a-zA-Z0-9_-]{11})['\"]" options:0 error:nil];
                            NSArray *matches = [regex matchesInString:desc options:0 range:NSMakeRange(0, MIN(2000, desc.length))];
                            for (NSTextCheckingResult *match in matches) {
                                if (match.numberOfRanges > 1) {
                                    NSString *potentialId = [desc substringWithRange:[match rangeAtIndex:1]];
                                    // Validate it looks like a video ID (not a hash or other string)
                                    if (![potentialId hasPrefix:@"0x"]) {
                                        return potentialId;
                                    }
                                }
                            }
                        }
                    }
                } @catch (NSException *e) {}
            }
        }
        
        responder = responder.nextResponder;
        depth++;
    }
    
    return nil;
}

%new
- (void)da_fetchAndApplyDeArrow:(NSString *)videoId originalTitle:(NSString *)originalTitle {
    // Check cache first
    DeArrowResult *cached = [[DeArrowClient sharedInstance] cachedResultForVideoId:videoId];
    if (cached && cached.hasTitle && [DeArrowPreferences titlesEnabled]) {
        [self da_applyDeArrowToCell:cached.title originalTitle:originalTitle];
        return;
    }
    
    // Fetch from API
    __weak typeof(self) weakSelf = self;
    [[DeArrowClient sharedInstance] fetchMetadataForVideoId:videoId highPriority:NO completion:^(DeArrowResult *result, NSError *error) {
        if (result && result.hasTitle && [DeArrowPreferences titlesEnabled]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf da_applyDeArrowToCell:result.title originalTitle:originalTitle];
            });
        }
    }];
}

%new
- (void)da_applyDeArrowToCell:(NSString *)newTitle originalTitle:(NSString *)originalTitle {
    DALog(@"✅ Applying DeArrow: '%@' -> '%@'", originalTitle, newTitle);
    
    // Update accessibility label (replace the title portion)
    NSString *currentLabel = self.accessibilityLabel;
    if (currentLabel && originalTitle) {
        NSString *newLabel = [currentLabel stringByReplacingOccurrencesOfString:originalTitle withString:newTitle];
        self.accessibilityLabel = newLabel;
    }
    
    // Now find and update the actual displayed text in the node
    @try {
        id node = [self valueForKey:@"asyncdisplaykit_node"];
        if (node) {
            [self da_updateTextInNode:node newTitle:newTitle originalTitle:originalTitle];
        }
    } @catch (NSException *e) {
        DALog(@"Exception updating node: %@", e);
    }
}

%new
- (void)da_updateTextInNode:(id)node newTitle:(NSString *)newTitle originalTitle:(NSString *)originalTitle {
    // Try to find text content in the node hierarchy
    @try {
        // Check if node has attributedText (ASTextNode)
        if ([node respondsToSelector:@selector(attributedText)]) {
            NSAttributedString *attrText = [node performSelector:@selector(attributedText)];
            if ([attrText.string containsString:originalTitle]) {
                NSMutableAttributedString *newAttr = [attrText mutableCopy];
                NSRange range = [newAttr.string rangeOfString:originalTitle];
                if (range.location != NSNotFound) {
                    [newAttr replaceCharactersInRange:range withString:newTitle];
                    [node setValue:newAttr forKey:@"attributedText"];
                    DALog(@"Updated attributedText in node");
                    
                    // Force layout update
                    if ([node respondsToSelector:@selector(setNeedsLayout)]) {
                        [node setNeedsLayout];
                    }
                }
            }
        }
        
        // Check children
        if ([node respondsToSelector:@selector(subnodes)]) {
            NSArray *subnodes = [node performSelector:@selector(subnodes)];
            for (id subnode in subnodes) {
                [self da_updateTextInNode:subnode newTitle:newTitle originalTitle:originalTitle];
            }
        }
    } @catch (NSException *e) {}
}

%new
- (void)da_checkAndApplyDeArrow {
    // Try to get the ASDisplayNode for this view
    id node = nil;
    @try {
        node = [self valueForKey:@"asyncdisplaykit_node"];
    } @catch (NSException *e) {}
    
    // Try to find videoId from the node/element hierarchy
    NSString *videoId = nil;
    
    // Method 1: Check the element's description for videoId pattern
    if (node) {
        @try {
            id element = [node valueForKey:@"element"];
            if (element) {
                NSString *desc = [element description];
                // Look for videoId pattern (11 chars, alphanumeric with - and _)
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"videoId[\":]\\s*[\"']?([a-zA-Z0-9_-]{11})" options:0 error:nil];
                NSTextCheckingResult *match = [regex firstMatchInString:desc options:0 range:NSMakeRange(0, MIN(2000, desc.length))];
                if (match && match.numberOfRanges > 1) {
                    videoId = [desc substringWithRange:[match rangeAtIndex:1]];
                    DALog(@"Found videoId from element: %@", videoId);
                }
            }
        } @catch (NSException *e) {}
    }
    
    // Method 2: Walk responder chain
    if (!videoId) {
        UIResponder *responder = self.nextResponder;
        int depth = 0;
        while (responder && !videoId && depth < 20) {
            videoId = extractVideoId(responder);
            responder = responder.nextResponder;
            depth++;
        }
    }
    
    if (!videoId) {
        DALog(@"Could not find videoId for this cell");
        return;
    }
    
    DALog(@"Processing cell with videoId: %@", videoId);
    
    // Check cache first, otherwise fetch
    DeArrowResult *cached = [[DeArrowClient sharedInstance] cachedResultForVideoId:videoId];
    if (cached && cached.hasTitle && [DeArrowPreferences titlesEnabled]) {
        [self da_replaceTitleWithDeArrow:cached.title];
    } else {
        // Fetch asynchronously
        __weak typeof(self) weakSelf = self;
        [[DeArrowClient sharedInstance] fetchMetadataForVideoId:videoId highPriority:NO completion:^(DeArrowResult *result, NSError *error) {
            if (result && result.hasTitle && [DeArrowPreferences titlesEnabled]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf da_replaceTitleWithDeArrow:result.title];
                });
            }
        }];
    }
}

%new
- (void)da_replaceTitleWithDeArrow:(NSString *)newTitle {
    // Find title labels in this view's hierarchy
    [self da_searchAndReplaceTitle:self withTitle:newTitle depth:0];
}

%new
- (BOOL)da_searchAndReplaceTitle:(UIView *)view withTitle:(NSString *)newTitle depth:(int)depth {
    if (depth > 10) return NO;
    
    // Check if this is a label with title-like text
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        // Title heuristics: long text, larger font, usually 2+ lines allowed
        if (label.text.length > 15 && label.font.pointSize >= 14 && 
            (label.numberOfLines == 0 || label.numberOfLines > 1)) {
            if (![label.text isEqualToString:newTitle]) {
                DALog(@"✅ Replacing title: '%@' -> '%@'", label.text, newTitle);
                label.text = newTitle;
                return YES;
            }
        }
    }
    
    // Check ASTextNode via _ASDisplayView
    if ([view isKindOfClass:%c(_ASDisplayView)]) {
        @try {
            id node = [view valueForKey:@"asyncdisplaykit_node"];
            if ([node isKindOfClass:%c(ASTextNode)]) {
                NSAttributedString *attrText = [node valueForKey:@"attributedText"];
                if (attrText.string.length > 15) {
                    UIFont *font = [attrText attribute:NSFontAttributeName atIndex:0 effectiveRange:nil];
                    if (font.pointSize >= 14) {
                        if (![attrText.string isEqualToString:newTitle]) {
                            NSDictionary *attrs = [attrText attributesAtIndex:0 effectiveRange:nil];
                            NSAttributedString *newAttr = [[NSAttributedString alloc] initWithString:newTitle attributes:attrs];
                            [node setValue:newAttr forKey:@"attributedText"];
                            DALog(@"✅ Replacing ASTextNode: '%@' -> '%@'", attrText.string, newTitle);
                            return YES;
                        }
                    }
                }
            }
        } @catch (NSException *e) {}
    }
    
    // Recurse into subviews
    for (UIView *subview in view.subviews) {
        if ([self da_searchAndReplaceTitle:subview withTitle:newTitle depth:depth+1]) {
            return YES;
        }
    }
    
    return NO;
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

/**
 * Hook: YTFormattedStringLabel
 * Purpose: Replace watch page title with DeArrow title
 * 
 * FLEX-verified: accessibilityIdentifier = "id.upload_metadata_editor_title_field"
 */
%hook YTFormattedStringLabel

- (void)setFormattedString:(id)formattedString {
    %orig;
    
    if (![DeArrowPreferences isEnabled] || ![DeArrowPreferences titlesEnabled] || ![DeArrowPreferences replaceInWatch]) {
        return;
    }
    
    // Check if this is the watch page title (FLEX-verified identifier)
    // Cast to UIView to access accessibilityIdentifier (YTFormattedStringLabel is a UILabel subclass)
    NSString *accessId = [(UIView *)self accessibilityIdentifier];
    if ([accessId isEqualToString:@"id.upload_metadata_editor_title_field"]) {
        DALog(@"🎬 Found watch title label with identifier");
        
        NSString *deArrowTitle = s_currentDeArrowTitle;
        
        if (deArrowTitle.length > 0) {
            DALog(@"✅ Replacing watch title with DeArrow: %@", deArrowTitle);
            
            // Create new formatted string with DeArrow title
            Class YTIFormattedStringClass = NSClassFromString(@"YTIFormattedString");
            id newFormattedString = [YTIFormattedStringClass performSelector:@selector(formattedStringWithString:) withObject:deArrowTitle];
            
            if (newFormattedString) {
                // Apply it (call orig again with new string)
                %orig(newFormattedString);
            }
        } else {
            DALog(@"No DeArrow title available yet");
        }
    }
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

