#import "NotificationDetailsViewController.h"
#import "NotificationDetailsViewController+Internal.h"

#import "WordPressAppDelegate.h"
#import <Simperium/Simperium.h>

#import "Blog.h"
#import "Notification.h"
#import <SVProgressHUD/SVProgressHUD.h>

#import "ContextManager.h"

#import "BlogService.h"
#import "CommentService.h"
#import "ReaderSiteService.h"

#import "WPWebViewController.h"
#import "WPImageViewController.h"

#import "ReaderCommentsViewController.h"
#import "StatsViewController.h"
#import "StatsViewAllTableViewController.h"
#import "EditCommentViewController.h"
#import "EditReplyViewController.h"

#import "SuggestionsTableView.h"
#import "SuggestionService.h"

#import "AppRatingUtility.h"

#import "WordPress-Swift.h"

#import "NSURL+Util.h"
#import "NSScanner+Helpers.h"
#import "NSObject+Helpers.h"
#import "NSDate+StringFormatting.h"
#import "NSString+Helpers.h"

#import "WPAppAnalytics.h"
#import "WPDeviceIdentification.h"



#pragma mark ==========================================================================================
#pragma mark Constants
#pragma mark ==========================================================================================

static NSTimeInterval NotificationFiveMinutes           = 60 * 5;
static NSInteger NotificationSectionCount               = 1;



#pragma mark ==========================================================================================
#pragma mark NotificationDetailsViewController
#pragma mark ==========================================================================================

@implementation NotificationDetailsViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Failsafe: Manually nuke the tableView dataSource and delegate. Make sure not to force a loadView event!
    if (!self.isViewLoaded) {
        return;
    }
    
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        self.restorationClass = [self class];
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self setupNavigationBar];
    [self setupMainView];
    [self setupTableView];
    [self setupTableViewCells];
    [self setupMediaDownloader];
    [self setupReplyTextView];
    [self setupSuggestionsView];
    [self setupKeyboardManager];
    [self setupNotificationListeners];

    [AppRatingUtility incrementSignificantEventForSection:@"notifications"];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self.tableView deselectSelectedRowWithAnimation:YES];
    [self.keyboardManager startListeningToKeyboardNotifications];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.keyboardManager stopListeningToKeyboardNotifications];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self adjustLayoutConstraintsIfNeeded];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];

    [self.tableView reloadData];
    [self adjustLayoutConstraintsIfNeeded];
}

- (void)reloadData
{
    // Hide the header, if needed
    NSMutableArray *blockGroups = [NSMutableArray array];
    
    if (_note.headerBlockGroup) {
        [blockGroups addObject:_note.headerBlockGroup];
    }
    
    if (_note.bodyBlockGroups) {
        [blockGroups addObjectsFromArray:_note.bodyBlockGroups];
    }
    
    self.blockGroups = blockGroups;
    
    // Reload UI
    self.title = self.note.title;
    [self.tableView reloadData];
    [self adjustLayoutConstraintsIfNeeded];
}


#pragma mark - Public Helpers

- (void)setupWithNotification:(Notification *)notification
{
    self.note = notification;
    [self loadViewIfNeeded];
    [self attachReplyViewIfNeeded];
    [self attachSuggestionsViewIfNeeded];
    [self attachEditActionIfNeeded];
    [self reloadData];
}


#pragma mark - Autolayout Helpers

- (NSDictionary *)layoutIdentifierMap
{
    if (_layoutIdentifierMap) {
        return _layoutIdentifierMap;
    }
    
    _layoutIdentifierMap = @{
        @(NoteBlockGroupTypeHeader)    : NoteBlockHeaderTableViewCell.layoutIdentifier,
        @(NoteBlockGroupTypeFooter)    : NoteBlockTextTableViewCell.layoutIdentifier,
        @(NoteBlockGroupTypeText)      : NoteBlockTextTableViewCell.layoutIdentifier,
        @(NoteBlockGroupTypeComment)   : NoteBlockCommentTableViewCell.layoutIdentifier,
        @(NoteBlockGroupTypeActions)   : NoteBlockActionsTableViewCell.layoutIdentifier,
        @(NoteBlockGroupTypeImage)     : NoteBlockImageTableViewCell.layoutIdentifier,
        @(NoteBlockGroupTypeUser)      : NoteBlockUserTableViewCell.layoutIdentifier
    };
    
    return _layoutIdentifierMap;
}

- (NSDictionary *)reuseIdentifierMap
{
    return @{
        @(NoteBlockGroupTypeHeader)     : NoteBlockHeaderTableViewCell.reuseIdentifier,
        @(NoteBlockGroupTypeFooter)     : NoteBlockTextTableViewCell.reuseIdentifier,
        @(NoteBlockGroupTypeText)       : NoteBlockTextTableViewCell.reuseIdentifier,
        @(NoteBlockGroupTypeComment)    : NoteBlockCommentTableViewCell.reuseIdentifier,
        @(NoteBlockGroupTypeActions)    : NoteBlockActionsTableViewCell.reuseIdentifier,
        @(NoteBlockGroupTypeImage)      : NoteBlockImageTableViewCell.reuseIdentifier,
        @(NoteBlockGroupTypeUser)       : NoteBlockUserTableViewCell.reuseIdentifier
    };
}




#pragma mark - UIViewController Restoration

+ (UIViewController *)viewControllerWithRestorationIdentifierPath:(NSArray *)identifierComponents coder:(NSCoder *)coder
{
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    NSString *noteID = [coder decodeObjectForKey:NSStringFromClass([Notification class])];
    if (!noteID) {
        return nil;
    }
    
    NSManagedObjectID *objectID = [context.persistentStoreCoordinator managedObjectIDForURIRepresentation:[NSURL URLWithString:noteID]];
    if (!objectID) {
        return nil;
    }
    
    NSError *error = nil;
    Notification *restoredNotification = (Notification *)[context existingObjectWithID:objectID error:&error];
    if (error || !restoredNotification) {
        return nil;
    }
    
    UIStoryboard *storyboard = [coder decodeObjectForKey:UIStateRestorationViewControllerStoryboardKey];
    if (!storyboard) {
        return nil;
    }
    
    NotificationDetailsViewController *vc   = [storyboard instantiateViewControllerWithIdentifier:NSStringFromClass([self class])];
    vc.restorationIdentifier                = [identifierComponents lastObject];
    vc.restorationClass                     = [NotificationDetailsViewController class];
    
    [vc setupWithNotification:restoredNotification];
    
    return vc;
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
    NSString *noteIdKey = NSStringFromClass([Notification class]);
    [coder encodeObject:[self.note.objectID.URIRepresentation absoluteString] forKey:noteIdKey];
    [super encodeRestorableStateWithCoder:coder];
}


#pragma mark - Helpers

- (NotificationBlockGroup *)blockGroupForIndexPath:(NSIndexPath *)indexPath
{
    return self.blockGroups[indexPath.row];
}


#pragma mark - UITableViewDelegate Methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return NotificationSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.blockGroups.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NotificationBlockGroup *blockGroup      = [self blockGroupForIndexPath:indexPath];
    NSString *layoutIdentifier              = self.layoutIdentifierMap[@(blockGroup.type)] ?: self.layoutIdentifierMap[@(NoteBlockGroupTypeText)];
    NoteBlockTableViewCell *tableViewCell   = [tableView dequeueReusableCellWithIdentifier:layoutIdentifier];

    [self downloadAndResizeMedia:indexPath blockGroup:blockGroup];
    [self setupCell:tableViewCell blockGroup:blockGroup];
    
    CGFloat height = [tableViewCell layoutHeightWithWidth:CGRectGetWidth(self.tableView.bounds)];

    return height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NotificationBlockGroup *blockGroup      = [self blockGroupForIndexPath:indexPath];
    NSString *reuseIdentifier               = self.reuseIdentifierMap[@(blockGroup.type)] ?: self.reuseIdentifierMap[@(NoteBlockGroupTypeText)];
    NoteBlockTableViewCell *cell            = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier forIndexPath:indexPath];

    [self setupSeparators:cell indexPath:indexPath];
    [self setupCell:cell blockGroup:blockGroup];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NotificationBlockGroup *group = [self blockGroupForIndexPath:indexPath];

    // User Blocks: Push the associated blog, if any
    if (group.type == NoteBlockGroupTypeUser) {
        
        NotificationBlock *block    = [group blockOfType:NoteBlockTypeUser];
        NSURL *siteURL              = [NSURL URLWithString:block.metaLinksHome];
        [self openURL:siteURL];
        
    // Header-Level: Push the resource associated with the note
    } else if (group.type == NoteBlockGroupTypeHeader) {
        
        [self openNotificationHeader:group];

    // Footer-Level:
    } else if (group.type == NoteBlockGroupTypeFooter) {
        
        // Note:
        // By convention, the last range is the one that always contains the targetURL.
        //
        NotificationBlock *block    = [group blockOfType:NoteBlockTypeText];
        NotificationRange *range    = block.ranges.lastObject;
        
        [self openURL:range.url];
    }
}


#pragma mark - Media Download Helper

- (void)downloadAndResizeMedia:(NSIndexPath *)indexPath blockGroup:(NotificationBlockGroup *)blockGroup
{
    //  Notes:
    //  -   We'll *only* download Media for Text and Comment Blocks
    //  -   Plus, we'll also resize the downloaded media cache *if needed*. This is meant to adjust images to
    //      better fit onscreen, whenever the device orientation changes (and in turn, the maxMediaEmbedWidth changes too).
    //
    NSSet *richBlockTypes           = [NSSet setWithObjects:@(NoteBlockTypeText), @(NoteBlockTypeComment), nil];
    NSSet *imageUrls                = [blockGroup imageUrlsForBlocksOfTypes:richBlockTypes];
    __weak __typeof(self) weakSelf  = self;
    
    void (^completion)(void)        = ^{
        
        // Workaround:
        // Performing the reload call, multiple times, without the UIViewAnimationOptionBeginFromCurrentState might lead
        // to a state in which the cell remains not visible.
        //
        [UIView animateWithDuration:0.25 delay:0.0 options:UIViewAnimationOptionOverrideInheritedDuration | UIViewAnimationOptionBeginFromCurrentState animations:^{
            [weakSelf.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        } completion:nil];
    };

    [self.mediaDownloader downloadMediaWithUrls:imageUrls maximumWidth:self.maxMediaEmbedWidth completion:completion];
    [self.mediaDownloader resizeMediaWithIncorrectSize:self.maxMediaEmbedWidth completion:completion];
}

- (CGFloat)maxMediaEmbedWidth
{
    UIEdgeInsets textPadding        = NoteBlockTextTableViewCell.defaultLabelPadding;
    CGFloat portraitWidth           = [UIDevice isPad] ? WPTableViewFixedWidth : CGRectGetWidth(self.view.bounds);
    CGFloat maxWidth                = portraitWidth - (textPadding.left + textPadding.right);
    
    return maxWidth;
}


#pragma mark - Associated Resources

- (void)openURL:(NSURL *)url
{
    //  NOTE:
    //  In this step, we attempt to match the URL tapped with any NotificationRange instance, contained in the note,
    //  and thus, recover the metadata!
    //
    NotificationRange *range    = [self.note notificationRangeWithUrl:url];
    BOOL success                = false;
    
    if (range.isPost) {
        success = [self displayReaderWithPostId:range.postID siteID:range.siteID];
    }
    
    if (range.isComment) {
        success = [self displayCommentsWithPostId:range.postID siteID:range.siteID];
    }
    
    if (!success && range.isStats) {
        success = [self displayStatsWithSiteID:range.siteID];
    }
    
    if (!success && range.isFollow) {
        success = [self displayFollowersWithSiteID:self.note.metaSiteID];
    }

    if (!success && range.isUser) {
        success = [self displayBrowseSite:range.siteID siteURL:range.url];
    }
    
    if (!success && url) {
        success = [self displayWebViewWithURL:url];
    }
    
    if (!success) {
        [self.tableView deselectSelectedRowWithAnimation:YES];
    }
}

- (void)openNotificationHeader:(NotificationBlockGroup *)header
{
    NSParameterAssert(header);
    NSParameterAssert(header.type == NoteBlockGroupTypeHeader);
    
    BOOL success = false;
    
    if (!success && self.note.isFollow) {
        NSURL *resourceURL = [NSURL URLWithString:self.note.url];
        success = [self displayBrowseSite:self.note.metaSiteID siteURL:resourceURL];
    }
    
    if (!success && self.note.metaCommentID) {
        success = [self displayCommentsWithPostId:self.note.metaPostID siteID:self.note.metaSiteID];
    }
    
    if (!success) {
        success = [self displayReaderWithPostId:self.note.metaPostID siteID:self.note.metaSiteID];
    }
    
    if (!success) {
        NSURL *resourceURL = [NSURL URLWithString:self.note.url];
        success = [self displayWebViewWithURL:resourceURL];
    }
    
    if (!success) {
        [self.tableView deselectSelectedRowWithAnimation:YES];
    }
}


#pragma mark - Helpers

- (BOOL)displayReaderWithPostId:(NSNumber *)postID siteID:(NSNumber *)siteID
{
    BOOL success = postID && siteID;
    if (success) {
        ReaderDetailViewController *readerViewController = [ReaderDetailViewController controllerWithPostID:postID siteID:siteID];
        [self.navigationController pushViewController:readerViewController animated:YES];
    }
    return success;
}

- (BOOL)displayCommentsWithPostId:(NSNumber *)postID siteID:(NSNumber *)siteID
{
    BOOL success = postID && siteID;
    if (success) {
        ReaderCommentsViewController *commentsViewController = [ReaderCommentsViewController controllerWithPostID:postID siteID:siteID];
        [commentsViewController setAllowsPushingPostDetails:YES];
        [self.navigationController pushViewController:commentsViewController animated:YES];
    }
    return success;
}

- (BOOL)displayStatsWithSiteID:(NSNumber *)siteID
{
    if (!siteID) {
        return false;
    }
    
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    BlogService *service            = [[BlogService alloc] initWithManagedObjectContext:context];
    Blog *blog                      = [service blogByBlogId:siteID];
    BOOL success                    = [blog supports:BlogFeatureStats];

    if (success) {
        StatsViewController *vc     = [[StatsViewController alloc] init];
        vc.blog = blog;
        [self.navigationController pushViewController:vc animated:YES];
    }
    return success;
}

- (BOOL)displayFollowersWithSiteID:(NSNumber *)siteID
{
    if (!siteID) {
        return false;
    }
    
    // Load the blog
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    BlogService *service            = [[BlogService alloc] initWithManagedObjectContext:context];
    Blog *blog                      = [service blogByBlogId:siteID];

    if (!blog || !blog.isHostedAtWPcom) {
        return NO;
    }

    // Push the Stats ViewController
    NSString *identifier            = NSStringFromClass([StatsViewAllTableViewController class]);
    
    NSBundle *statsBundle = [NSBundle bundleForClass:[WPStatsViewController class]];
    NSString *path = [statsBundle pathForResource:@"WordPressCom-Stats-iOS" ofType:@"bundle"];
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    UIStoryboard *statsStoryboard   = [UIStoryboard storyboardWithName:@"SiteStats" bundle:bundle];
    StatsViewAllTableViewController *vc = [statsStoryboard instantiateViewControllerWithIdentifier:identifier];
    NSAssert(vc, @"Couldn't instantiate StatsViewAllTableViewController");
    
    vc.selectedDate                = [NSDate date];
    vc.statsSection                = StatsSectionFollowers;
    vc.statsSubSection             = StatsSubSectionFollowersDotCom;
    vc.statsService                = [[WPStatsService alloc] initWithSiteId:blog.dotComID
                                                               siteTimeZone:[service timeZoneForBlog:blog]
                                                                oauth2Token:blog.authToken
                                                 andCacheExpirationInterval:NotificationFiveMinutes];
    
    [self.navigationController pushViewController:vc animated:YES];
    
    return YES;
}

- (BOOL)displayWebViewWithURL:(NSURL *)url
{
    BOOL success = [url isKindOfClass:[NSURL class]];
    if (!success) {
        return NO;
    }
    
    WPWebViewController *webViewController  = [WPWebViewController authenticatedWebViewController:url];
    UINavigationController *navController   = [[UINavigationController alloc] initWithRootViewController:webViewController];
    
    [self presentViewController:navController animated:YES completion:nil];
    
    return success;
}

- (BOOL)displayBrowseSite:(NSNumber *)siteID siteURL:(NSURL *)siteURL
{
    if (![siteID isKindOfClass:[NSNumber class]]) {
        return NO;
    }

    ReaderStreamViewController *browseViewController = [ReaderStreamViewController controllerWithSiteID:siteID isFeed:NO];
    [self.navigationController pushViewController:browseViewController animated:YES];
    
    return YES;
}

- (BOOL)displayFullscreenImage:(UIImage *)image
{
    if (!image) {
        return NO;
    }
    
    WPImageViewController *imageViewController = [[WPImageViewController alloc] initWithImage:image];
    imageViewController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    imageViewController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:imageViewController animated:YES completion:nil];
    
    return YES;
}


#pragma mark - Action Handlers

- (void)followSiteWithBlock:(NotificationBlock *)block
{
    
    [WPAppAnalytics track:WPAnalyticsStatNotificationsSiteFollowAction withBlogID:block.metaSiteID];
    
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    ReaderSiteService *service      = [[ReaderSiteService alloc] initWithManagedObjectContext:context];
    __typeof(self) __weak weakSelf  = self;
    
    [service followSiteWithID:block.metaSiteID.integerValue success:nil failure:^(NSError *error) {
        [block removeActionOverrideForKey:NoteActionFollowKey];
        [weakSelf reloadData];
    }];
    
    [block setActionOverrideValue:@(true) forKey:NoteActionFollowKey];
}

- (void)unfollowSiteWithBlock:(NotificationBlock *)block
{
    [WPAppAnalytics track:WPAnalyticsStatNotificationsSiteUnfollowAction withBlogID:block.metaSiteID];
    
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    ReaderSiteService *service      = [[ReaderSiteService alloc] initWithManagedObjectContext:context];
    __typeof(self) __weak weakSelf  = self;
    
    [service unfollowSiteWithID:block.metaSiteID.integerValue success:nil failure:^(NSError *error) {
        [block removeActionOverrideForKey:NoteActionFollowKey];
        [weakSelf reloadData];
    }];
    
    [block setActionOverrideValue:@(false) forKey:NoteActionFollowKey];
}

- (void)likeCommentWithBlock:(NotificationBlock *)block
{

    [WPAppAnalytics track:WPAnalyticsStatNotificationsCommentLiked withBlogID:block.metaSiteID];
    
    // If the associated comment is *not* approved, let's attempt to auto-approve it, automatically
    if (!block.isCommentApproved) {
        [self approveCommentWithBlock:block];
    }

    // Proceed toggling the Like field
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
    __typeof(self) __weak weakSelf  = self;
    
    [service likeCommentWithID:block.metaCommentID siteID:block.metaSiteID success:nil failure:^(NSError *error) {
        [block removeActionOverrideForKey:NoteActionLikeKey];
        [weakSelf reloadData];
    }];
    
    [block setActionOverrideValue:@(true) forKey:NoteActionLikeKey];
}

- (void)unlikeCommentWithBlock:(NotificationBlock *)block
{
    [WPAppAnalytics track:WPAnalyticsStatNotificationsCommentUnliked withBlogID:block.metaSiteID];
    
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
    __typeof(self) __weak weakSelf  = self;
    
    [service unlikeCommentWithID:block.metaCommentID siteID:block.metaSiteID success:nil failure:^(NSError *error) {
        [block removeActionOverrideForKey:NoteActionLikeKey];
        [weakSelf reloadData];
    }];
    
    [block setActionOverrideValue:@(false) forKey:NoteActionLikeKey];
}

- (void)approveCommentWithBlock:(NotificationBlock *)block
{
    [WPAppAnalytics track:WPAnalyticsStatNotificationsCommentApproved withBlogID:block.metaSiteID];
    
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
    __typeof(self) __weak weakSelf  = self;
    
    [service approveCommentWithID:block.metaCommentID siteID:block.metaSiteID success:nil failure:^(NSError *error) {
        [block removeActionOverrideForKey:NoteActionApproveKey];
        [weakSelf reloadData];
    }];

    [block setActionOverrideValue:@(true) forKey:NoteActionApproveKey];
    [self.tableView reloadData];
}

- (void)unapproveCommentWithBlock:(NotificationBlock *)block
{
    [WPAppAnalytics track:WPAnalyticsStatNotificationsCommentUnapproved withBlogID:block.metaSiteID];
  
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
    __typeof(self) __weak weakSelf  = self;
    
    [service unapproveCommentWithID:block.metaCommentID siteID:block.metaSiteID success:nil failure:^(NSError *error) {
        [block removeActionOverrideForKey:NoteActionApproveKey];
        [weakSelf reloadData];
    }];
    
    [block setActionOverrideValue:@(false) forKey:NoteActionApproveKey];
    [self.tableView reloadData];
}

- (void)spamCommentWithBlock:(NotificationBlock *)block
{
    NSParameterAssert(block);
    NSParameterAssert(self.onDeletionRequestCallback);
    
    // Spam Action
    NotificationDeletionActionBlock spamAction = ^(NotificationDeletionCompletionBlock onCompletion) {
        NSParameterAssert(onCompletion);
        
        NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
        CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
        
        [service spamCommentWithID:block.metaCommentID siteID:block.metaSiteID success:^{
            onCompletion(YES);
        } failure:^(NSError *error){
            onCompletion(NO);
        }];
        
        [WPAppAnalytics track:WPAnalyticsStatNotificationsCommentFlaggedAsSpam withBlogID:block.metaSiteID];
    };
    
    // Hit the DeletionRequest Callback
    self.onDeletionRequestCallback(spamAction);    
    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)trashCommentWithBlock:(NotificationBlock *)block
{
    NSParameterAssert(block);
    NSParameterAssert(self.onDeletionRequestCallback);
    
    // Trash Action
    NotificationDeletionActionBlock deletionAction =  ^(NotificationDeletionCompletionBlock onCompletion) {
        NSParameterAssert(onCompletion);
        
        NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
        CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
        
        [service deleteCommentWithID:block.metaCommentID siteID:block.metaSiteID success:^{
            onCompletion(YES);
        } failure:^(NSError *error) {
            onCompletion(NO);
        }];
        
        [WPAppAnalytics track:WPAnalyticsStatNotificationsCommentTrashed withBlogID:block.metaSiteID];
    };
    
    // Hit the DeletionRequest Callback
    self.onDeletionRequestCallback(deletionAction);
    [self.navigationController popToRootViewControllerAnimated:YES];
}


#pragma mark - Replying Comments

- (void)editReplyWithBlock:(NotificationBlock *)block
{
    EditReplyViewController *editViewController     = [EditReplyViewController newReplyViewControllerForSiteID:self.note.metaSiteID];
    
    editViewController.onCompletion                 = ^(BOOL hasNewContent, NSString *newContent) {
        [self dismissViewControllerAnimated:YES completion:^{
            if (hasNewContent) {
                [self sendReplyWithBlock:block content:newContent];
            }
        }];
    };
    
    UINavigationController *navController           = [[UINavigationController alloc] initWithRootViewController:editViewController];
    navController.modalPresentationStyle            = UIModalPresentationFormSheet;
    navController.modalTransitionStyle              = UIModalTransitionStyleCoverVertical;
    navController.navigationBar.translucent         = NO;
    
    [self presentViewController:navController animated:true completion:nil];
}

- (void)sendReplyWithBlock:(NotificationBlock *)block content:(NSString *)content
{
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
    
    [service replyToCommentWithID:block.metaCommentID
                           siteID:block.metaSiteID
                          content:content
                          success:^{
                              NSString *successMessage = NSLocalizedString(@"Reply Sent!", @"The app successfully sent a comment");
                              [SVProgressHUD showSuccessWithStatus:successMessage];
                          }
                          failure:^(NSError *error) {
                              [self handleReplyErrorWithBlock:block content:content];
                          }];
}

- (void)handleReplyErrorWithBlock:(NotificationBlock *)block content:(NSString *)content
{
    NSString *message = NSLocalizedString(@"There has been an unexpected error while sending your reply", nil);
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil
                                                                             message:message
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    [alertController addCancelActionWithTitle:NSLocalizedString(@"Cancel", nil) handler:nil];
    [alertController addDefaultActionWithTitle:NSLocalizedString(@"Try Again", nil) handler:^(UIAlertAction *action) {
        [self sendReplyWithBlock:block content:content];
    }];
    
    // Note: This viewController might not be visible anymore
    [alertController presentFromRootViewController];
}


#pragma mark - Editing Comments

- (void)editCommentWithBlock:(NotificationBlock *)block
{
    EditCommentViewController *editViewController   = [EditCommentViewController newEditViewController];
    
    editViewController.content                      = block.text;
    editViewController.onCompletion                 = ^(BOOL hasNewContent, NSString *newContent) {
        [self dismissViewControllerAnimated:YES completion:^{
            if (hasNewContent) {
                [self updateCommentWithBlock:block content:newContent];
            }
        }];
    };
    
    UINavigationController *navController           = [[UINavigationController alloc] initWithRootViewController:editViewController];
    navController.modalPresentationStyle            = UIModalPresentationFormSheet;
    navController.modalTransitionStyle              = UIModalTransitionStyleCoverVertical;
    navController.navigationBar.translucent         = NO;
    
    [self presentViewController:navController animated:true completion:nil];

}

- (void)updateCommentWithBlock:(NotificationBlock *)block content:(NSString *)content
{
    // Local Override: Temporary hack until Simperium reflects the REST op
    block.textOverride = content;
    [self reloadData];
    
    // Hit the backend
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
    
    [service updateCommentWithID:block.metaCommentID siteID:block.metaSiteID content:content success:nil failure:^(NSError *error) {
        [self handleCommentUpdateErrorWithBlock:block content:content];
    }];
}

- (void)handleCommentUpdateErrorWithBlock:(NotificationBlock *)block content:(NSString *)content
{
    NSString *message = NSLocalizedString(@"There has been an unexpected error while updating your comment", nil);
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil
                                                                             message:message
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    [alertController addCancelActionWithTitle:NSLocalizedString(@"Give Up", nil) handler:^(UIAlertAction *action) {
        block.textOverride = nil;
        [self reloadData];
    }];
    
    [alertController addDefaultActionWithTitle:NSLocalizedString(@"Try Again", nil) handler:^(UIAlertAction *action) {
        [self updateCommentWithBlock:block content:content];
    }];
    
    // Note: This viewController might not be visible anymore
    [alertController presentFromRootViewController];
}

@end
