#import "CreateNewBlogViewController.h"
#import <EmailChecker/EmailChecker.h>
#import <QuartzCore/QuartzCore.h>
#import "SupportViewController.h"
#import "WordPressComApi.h"
#import "WPNUXMainButton.h"
#import "WPNUXSecondaryButton.h"
#import "WPPostViewController.h"
#import "WPWalkthroughTextField.h"
#import "WPAsyncBlockOperation.h"
#import "WPComLanguages.h"
#import "WPWalkthroughOverlayView.h"
#import "SelectWPComLanguageViewController.h"
#import "WPNUXUtility.h"
#import "WPWebViewController.h"
#import "WPStyleGuide.h"
#import "WPFontManager.h"
#import "UILabel+SuggestSize.h"
#import "WPAccount.h"
#import "Blog.h"
#import "WordPressComOAuthClient.h"
#import "WordPressComServiceRemote.h"
#import "AccountService.h"
#import "BlogService.h"
#import "ContextManager.h"
#import "NSString+XMLExtensions.h"
#import "Constants.h"

#import "WordPress-Swift.h"

@interface CreateNewBlogViewController ()<UITextFieldDelegate,UIGestureRecognizerDelegate> {
    // Page 1
    WPNUXSecondaryButton *_cancelButton;
    UILabel *_titleLabel;
    UILabel *_siteAddressWPComLabel;
    WPWalkthroughTextField *_siteTitleField;
    WPNUXMainButton *_createBlogButton;
    WPWalkthroughTextField *_siteAddressField;
    
    NSOperationQueue *_operationQueue;
    
    BOOL _authenticating;
    BOOL _keyboardVisible;
    BOOL _userDefinedSiteAddress;
    CGFloat _keyboardOffset;
    
    NSDictionary *_currentLanguage;
}

@end

@implementation CreateNewBlogViewController

static CGFloat const CreateAccountAndBlogStandardOffset             = 15.0;
static CGFloat const CreateAccountAndBlogMaxTextWidth               = 260.0;
static CGFloat const CreateAccountAndBlogTextFieldWidth             = 320.0;
static CGFloat const CreateAccountAndBlogTextFieldHeight            = 44.0;
static CGFloat const CreateAccountAndBlogTextFieldPhoneHeight       = 38.0;
static CGFloat const CreateAccountAndBlogiOS7StatusBarOffset        = 20.0;
static CGFloat const CreateAccountAndBlogButtonWidth                = 290.0;
static CGFloat const CreateAccountAndBlogButtonHeight               = 41.0;

static UIEdgeInsets const CreateAccountAndBlogCancelButtonPadding     = {1.0, 0.0, 0.0, 0.0};
static UIEdgeInsets const CreateAccountAndBlogCancelButtonPaddingPad  = {1.0, 13.0, 0.0, 0.0};

static UIEdgeInsets const CreateAccountAndBlogHelpButtonPadding     = {1.0, 0.0, 0.0, 13.0};
static UIEdgeInsets const CreateAccountAndBlogHelpButtonPaddingPad  = {1.0, 0.0, 0.0, 20.0};

- (instancetype)init
{
    self = [super init];
    if (self) {
        _operationQueue = [[NSOperationQueue alloc] init];
        _currentLanguage = [WPComLanguages currentLanguage];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.view.backgroundColor = [WPStyleGuide wordPressBlue];
    
    [self initializeView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidShow)
                                                 name:UIKeyboardDidShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidHide)
                                                 name:UIKeyboardDidHideNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    [self layoutControls];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if (IS_IPHONE) {
        return UIInterfaceOrientationMaskPortrait;
    }
    
    return UIInterfaceOrientationMaskAll;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
                                         duration:(NSTimeInterval)duration
{
    [self layoutControls];
}

#pragma mark - UITextField Delegate methods

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    if (textField == _siteTitleField) {
        [_siteAddressField becomeFirstResponder];
    } else if (textField == _siteAddressField) {
        if (_createBlogButton.enabled) {
            [self createBlogButtonAction];
        }
    }
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string
{
    NSArray *fields = @[_siteTitleField, _siteAddressField];
    
    NSMutableString *updatedString = [[NSMutableString alloc] initWithString:textField.text];
    [updatedString replaceCharactersInRange:range withString:string];
    
    if ([fields containsObject:textField]) {
        [self updateCreateBlogButtonForTextfield:textField andUpdatedString:updatedString];
    }
    
    if ([textField isEqual:_siteAddressField]) {
        _userDefinedSiteAddress = YES;
    }
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    if ([textField isEqual:_siteTitleField]) {
        if ([[_siteAddressField.text trim] length] == 0 || !_userDefinedSiteAddress) {
            NSCharacterSet *charactersToRemove = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
            NSString *strippedReplacement = [[_siteTitleField.text.lowercaseString componentsSeparatedByCharactersInSet:charactersToRemove] componentsJoinedByString:@""];
            _siteAddressField.text = strippedReplacement;
            _userDefinedSiteAddress = NO;
            [self updateCreateBlogButtonForTextfield:_siteAddressField andUpdatedString:_siteAddressField.text];
        }
    }
}

- (void)updateCreateBlogButtonForTextfield:(UITextField *)textField andUpdatedString:(NSString *)updatedString
{
    BOOL isSiteTitleFilled = [self isSiteTitleFilled];
    BOOL isSiteAddressFilled = [self isSiteAddressFilled];
    BOOL updatedStringHasContent = [[updatedString trim] length] != 0;
    
    if (textField == _siteTitleField) {
        isSiteTitleFilled = updatedStringHasContent;
    } else if (textField == _siteAddressField) {
        isSiteAddressFilled = updatedStringHasContent;
    }
    
    _createBlogButton.enabled = isSiteTitleFilled && isSiteAddressFilled;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    _createBlogButton.enabled = [self fieldsValid];
    return YES;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
    _createBlogButton.enabled = [self fieldsValid];
    return YES;
}

#pragma mark - Private Methods

- (void)initializeView
{
    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                        action:@selector(viewWasTapped:)];
    gestureRecognizer.numberOfTapsRequired = 1;
    gestureRecognizer.cancelsTouchesInView = YES;
    [self.view addGestureRecognizer:gestureRecognizer];
    
    [self addControls];
    [self layoutControls];
}

- (void)addControls
{
    // Add Cancel Button
    if (_cancelButton == nil) {
        _cancelButton = [[WPNUXSecondaryButton alloc] init];
        [_cancelButton addTarget:self action:@selector(cancelButtonAction) forControlEvents:UIControlEventTouchUpInside];
        [_cancelButton sizeToFit];
        _cancelButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
        [self.view addSubview:_cancelButton];
    }
    
    // Add Title
    if (_titleLabel == nil) {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.attributedText = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Create WordPress.com blog", @"Create WordPress.com blog Title")
                                                                     attributes:[WPNUXUtility titleAttributesWithColor:[UIColor whiteColor]]];
        _titleLabel.numberOfLines = 0;
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin;
        [self.view addSubview:_titleLabel];
    }
    
    // Add Site Title
    if (_siteTitleField == nil) {
        _siteTitleField = [[WPWalkthroughTextField alloc] initWithLeftViewImage:[UIImage imageNamed:@"icon-username-field"]];
        _siteTitleField.backgroundColor = [UIColor whiteColor];
        _siteTitleField.placeholder = NSLocalizedString(@"Title", nil);
        _siteTitleField.font = [WPNUXUtility textFieldFont];
        _siteTitleField.adjustsFontSizeToFitWidth = YES;
        _siteTitleField.delegate = self;
        _siteTitleField.autocorrectionType = UITextAutocorrectionTypeNo;
        _siteTitleField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _siteTitleField.showTopLineSeparator = YES;
        _siteTitleField.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin;
        _siteTitleField.accessibilityIdentifier = @"Title";
        _siteTitleField.returnKeyType = UIReturnKeyNext;
        [self.view addSubview:_siteTitleField];
    }
    
    // Add Site Address
    if (_siteAddressField == nil) {
        _siteAddressField = [[WPWalkthroughTextField alloc] initWithLeftViewImage:[UIImage imageNamed:@"icon-url-field"]];
        _siteAddressField.backgroundColor = [UIColor whiteColor];
        _siteAddressField.placeholder = NSLocalizedString(@"Blog Address", nil);
        _siteAddressField.font = [WPNUXUtility textFieldFont];
        _siteAddressField.adjustsFontSizeToFitWidth = YES;
        _siteAddressField.delegate = self;
        _siteAddressField.autocorrectionType = UITextAutocorrectionTypeNo;
        _siteAddressField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _siteAddressField.returnKeyType = UIReturnKeyDone;
        _siteAddressField.showTopLineSeparator = YES;
        _siteAddressField.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin;
        _siteAddressField.accessibilityIdentifier = @"Blog Address";
        [self.view addSubview:_siteAddressField];
        
        // add .wordpress.com label to textfield
        _siteAddressWPComLabel = [[UILabel alloc] init];
        _siteAddressWPComLabel.text = @".wordpress.com";
        _siteAddressWPComLabel.textAlignment = NSTextAlignmentCenter;
        _siteAddressWPComLabel.font = [WPNUXUtility descriptionTextFont];
        _siteAddressWPComLabel.textColor = [WPStyleGuide allTAllShadeGrey];
        [_siteAddressWPComLabel sizeToFit];
        
        UIEdgeInsets siteAddressTextInsets = [(WPWalkthroughTextField *)_siteAddressField textInsets];
        siteAddressTextInsets.right += _siteAddressWPComLabel.frame.size.width + 10;
        [(WPWalkthroughTextField *)_siteAddressField setTextInsets:siteAddressTextInsets];
        [_siteAddressField addSubview:_siteAddressWPComLabel];
    }
    
    // Add Next Button
    if (_createBlogButton == nil) {
        _createBlogButton = [[WPNUXMainButton alloc] init];
        [_createBlogButton setTitle:NSLocalizedString(@"Create WordPress.com blog", nil) forState:UIControlStateNormal];
        _createBlogButton.enabled = NO;
        [_createBlogButton addTarget:self action:@selector(createBlogButtonAction) forControlEvents:UIControlEventTouchUpInside];
        [_createBlogButton sizeToFit];
        _createBlogButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin;
        [self.view addSubview:_createBlogButton];
    }
}

- (void)layoutControls
{
    CGFloat x,y;
    
    CGFloat viewWidth = CGRectGetWidth(self.view.bounds);
    CGFloat viewHeight = CGRectGetHeight([UIScreen mainScreen].bounds);
    
    UIEdgeInsets cancelButtonPadding = [UIDevice isPad] ? CreateAccountAndBlogCancelButtonPaddingPad : CreateAccountAndBlogCancelButtonPadding;
    
    // Layout Cancel Button
    x = cancelButtonPadding.left;
    y = CreateAccountAndBlogiOS7StatusBarOffset + cancelButtonPadding.top;
    _cancelButton.frame = CGRectMake(x, y, CGRectGetWidth(_cancelButton.frame), CreateAccountAndBlogButtonHeight);
    
    // Layout the controls starting out from y of 0, then offset them once the height of the controls
    // is accurately calculated we can determine the vertical center and adjust everything accordingly.
    
    // Layout Title
    CGSize titleSize = [_titleLabel suggestedSizeForWidth:CreateAccountAndBlogMaxTextWidth];
    x = (viewWidth - titleSize.width)/2.0;
    y = 0;
    _titleLabel.frame = CGRectIntegral(CGRectMake(x, y, titleSize.width, titleSize.height));
    
    // In order to fit controls ontol all phones, the textField height is smaller on iPhones
    // versus iPads.
    CGFloat textFieldHeight = IS_IPAD ? CreateAccountAndBlogTextFieldHeight: CreateAccountAndBlogTextFieldPhoneHeight;
    
    // Layout Site Title
    x = (viewWidth - CreateAccountAndBlogTextFieldWidth)/2.0;
    y = CGRectGetMaxY(_titleLabel.frame) - 1;
    _siteTitleField.frame = CGRectIntegral(CGRectMake(x, y, CreateAccountAndBlogTextFieldWidth, textFieldHeight));
    
    // Layout Site Address
    x = (viewWidth - CreateAccountAndBlogTextFieldWidth)/2.0;
    y = CGRectGetMaxY(_siteTitleField.frame) - 1;
    _siteAddressField.frame = CGRectIntegral(CGRectMake(x, y, CreateAccountAndBlogTextFieldWidth, textFieldHeight));
    
    // Layout WordPressCom Label
    [_siteAddressWPComLabel sizeToFit];
    CGSize wordPressComLabelSize = _siteAddressWPComLabel.frame.size;
    wordPressComLabelSize.height = _siteAddressField.frame.size.height - 10;
    wordPressComLabelSize.width += 10;
    _siteAddressWPComLabel.frame = CGRectMake(_siteAddressField.frame.size.width - wordPressComLabelSize.width - 5,
                                              (_siteAddressField.frame.size.height - wordPressComLabelSize.height) / 2 - 1,
                                              wordPressComLabelSize.width,
                                              wordPressComLabelSize.height);
    
    // Layout Create Account Button
    x = (viewWidth - CreateAccountAndBlogButtonWidth)/2.0;
    y = CGRectGetMaxY(_siteAddressField.frame) + CreateAccountAndBlogStandardOffset;
    _createBlogButton.frame = CGRectIntegral(CGRectMake(x,
                                                           y,
                                                           CreateAccountAndBlogButtonWidth,
                                                           CreateAccountAndBlogButtonHeight));
    
    NSArray *controls = @[_titleLabel, _siteTitleField,
                          _createBlogButton, _siteAddressField];
    [WPNUXUtility centerViews:controls withStartingView:_titleLabel andEndingView:_createBlogButton forHeight:viewHeight];
}

- (IBAction)cancelButtonAction
{
    [self.navigationController popViewControllerAnimated:YES];
}

- (IBAction)viewWasTapped:(UITapGestureRecognizer *)gestureRecognizer
{
    [self.view endEditing:YES];
}

- (IBAction)createBlogButtonAction
{
    [self.view endEditing:YES];
    
    if (![self fieldsValid]) {
        [self showFieldsNotFilledError];
        return;
    }
    
    [self createUserAndSite];
}

- (IBAction)TOSLabelWasTapped
{
    NSURL *targetURL = [NSURL URLWithString:WPAutomatticTermsOfServiceURL];
    WPWebViewController *webViewController = [WPWebViewController webViewControllerWithURL:targetURL];
    
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:webViewController];
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)keyboardWillShow:(NSNotification *)notification
{
    NSDictionary *keyboardInfo = notification.userInfo;
    CGFloat animationDuration = [[keyboardInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue];
    CGRect keyboardFrame = [[keyboardInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    keyboardFrame = [self.view convertRect:keyboardFrame fromView:nil];
    
    CGFloat newKeyboardOffset = (CGRectGetMaxY(_createBlogButton.frame) - CGRectGetMinY(keyboardFrame)) + CreateAccountAndBlogStandardOffset;
    
    // make sure keyboard offset is greater than 0, otherwise do not move controls
    if (newKeyboardOffset < 0) {
        return;
    }
    
    [UIView animateWithDuration:animationDuration animations:^{
        for (UIControl *control in [self controlsToMoveDuringKeyboardTransition]) {
            CGRect frame = control.frame;
            frame.origin.y -= newKeyboardOffset;
            control.frame = frame;
        }
        
        for (UIControl *control in [self controlsToShowOrHideDuringKeyboardTransition]) {
            control.alpha = 0.0;
        }
    } completion:^(BOOL finished) {
        _keyboardOffset += newKeyboardOffset;
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    NSDictionary *keyboardInfo = notification.userInfo;
    CGFloat animationDuration = [[keyboardInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue];
    
    CGFloat currentKeyboardOffset = _keyboardOffset;
    _keyboardOffset = 0;
    
    [UIView animateWithDuration:animationDuration animations:^{
        for (UIControl *control in [self controlsToMoveDuringKeyboardTransition]) {
            CGRect frame = control.frame;
            frame.origin.y += currentKeyboardOffset;
            control.frame = frame;
        }
        
        for (UIControl *control in [self controlsToShowOrHideDuringKeyboardTransition]) {
            control.alpha = 1.0;
        }
    }];
}

- (void)keyboardDidShow
{
    _keyboardVisible = YES;
}

- (void)keyboardDidHide
{
    _keyboardVisible = NO;
}

- (NSArray *)controlsToMoveDuringKeyboardTransition
{
    return @[_siteTitleField, _createBlogButton, _siteAddressField];
}

- (NSArray *)controlsToShowOrHideDuringKeyboardTransition
{
    return @[_titleLabel, _cancelButton];
}

- (void)displayRemoteError:(NSError *)error
{
    NSString *errorMessage = [error.userInfo objectForKey:WordPressComApiErrorMessageKey];
    [self showError:errorMessage];
}

- (BOOL)isSiteTitleFilled
{
    return ([[_siteTitleField.text trim] length] != 0);
}

- (BOOL)isSiteAddressFilled
{
    return ([[_siteAddressField.text trim] length] != 0);
}

- (BOOL)fieldsValid
{
    return [self isSiteTitleFilled] && [self isSiteAddressFilled];
}

- (void)showFieldsNotFilledError
{
    [self showError:NSLocalizedString(@"Please fill out all the fields", nil)];
}

- (NSString *)getSiteAddressWithoutWordPressDotCom
{
    NSRegularExpression *dotCom = [NSRegularExpression regularExpressionWithPattern:@"\\.wordpress\\.com/?$"
                                                                            options:NSRegularExpressionCaseInsensitive error:nil];
    return [dotCom stringByReplacingMatchesInString:_siteAddressField.text options:0
                                              range:NSMakeRange(0, [_siteAddressField.text length]) withTemplate:@""];
}

- (void)showError:(NSString *)message
{
    WPWalkthroughOverlayView *overlayView = [[WPWalkthroughOverlayView alloc] initWithFrame:self.view.bounds];
    overlayView.overlayTitle = NSLocalizedString(@"Error", nil);
    overlayView.overlayDescription = message;
    overlayView.dismissCompletionBlock = ^(WPWalkthroughOverlayView *overlayView){
        [overlayView dismiss];
    };
    [self.view addSubview:overlayView];
}

- (void)setAuthenticating:(BOOL)authenticating
{
    _authenticating = authenticating;
    _createBlogButton.enabled = !authenticating;
    [_createBlogButton showActivityIndicator:authenticating];
}

- (void)createUserAndSite
{
    if (_authenticating) {
        return;
    }
    
    [self setAuthenticating:YES];
    
    // The site must be validated prior to making an account. Without validation,
    // the situation could exist where a user account is created, but the site creation
    // fails.
    WPAsyncBlockOperation *siteValidation = [WPAsyncBlockOperation operationWithBlock:^(WPAsyncBlockOperation *operation) {
        WordPressComServiceSuccessBlock blogValidationSuccess = ^(NSDictionary *responseDictionary) {
            [operation didSucceed];
        };
        WordPressComServiceFailureBlock blogValidationFailure = ^(NSError *error) {
            [operation didFail];
            [self setAuthenticating:NO];
            [self displayRemoteError:error];
        };
        
        NSString *languageId = [_currentLanguage stringForKey:@"lang_id"];
        
        WordPressComApi *api = [WordPressComApi anonymousApi];
        WordPressComServiceRemote *service = [[WordPressComServiceRemote alloc] initWithApi:api];
        
        [service validateWPComBlogWithUrl:[self getSiteAddressWithoutWordPressDotCom]
                             andBlogTitle:_siteTitleField.text
                            andLanguageId:languageId
                                  success:blogValidationSuccess
                                  failure:blogValidationFailure];
    }];
    
    WPAsyncBlockOperation *blogCreation = [WPAsyncBlockOperation operationWithBlock:^(WPAsyncBlockOperation *operation){
        WordPressComServiceSuccessBlock createBlogSuccess = ^(NSDictionary *responseDictionary){
            [WPAnalytics track:WPAnalyticsStatCreatedAccount];
            [operation didSucceed];
            
            NSMutableDictionary *blogOptions = [[responseDictionary dictionaryForKey:@"blog_details"] mutableCopy];
            if ([blogOptions objectForKey:@"blogname"]) {
                [blogOptions setObject:[blogOptions objectForKey:@"blogname"] forKey:@"blogName"];
                [blogOptions removeObjectForKey:@"blogname"];
            }
            
            NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
            AccountService *accountService = [[AccountService alloc] initWithManagedObjectContext:context];
            BlogService *blogService = [[BlogService alloc] initWithManagedObjectContext:context];
            WPAccount *defaultAccount = [accountService defaultWordPressComAccount];
            
            Blog *blog = [blogService findBlogWithXmlrpc:blogOptions[@"xmlrpc"] inAccount:defaultAccount];
            if (!blog) {
                blog = [blogService createBlogWithAccount:defaultAccount];
                blog.xmlrpc = blogOptions[@"xmlrpc"];
            }
            blog.blogID = [blogOptions numberForKey:@"blogid"];
            blog.blogName = [blogOptions[@"blogname"] stringByDecodingXMLCharacters];
            blog.url = blogOptions[@"url"];
            defaultAccount.defaultBlog = blog;
            
            [[ContextManager sharedInstance] saveContext:context];
            
            [accountService updateUserDetailsForAccount:defaultAccount success:nil failure:nil];
            [blogService syncBlog:blog];
            [WPAnalytics refreshMetadata];
            [self setAuthenticating:NO];
            [self dismissViewControllerAnimated:YES completion:nil];
        };
        WordPressComServiceFailureBlock createBlogFailure = ^(NSError *error) {
            DDLogError(@"Failed creating blog: %@", error);
            [self setAuthenticating:NO];
            [operation didFail];
            [self displayRemoteError:error];
        };
        
        NSString *languageId = [_currentLanguage stringForKey:@"lang_id"];
        
        NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
        AccountService *accountService = [[AccountService alloc] initWithManagedObjectContext:context];
        
        WordPressComApi *api = [[accountService defaultWordPressComAccount] restApi];
        WordPressComServiceRemote *service = [[WordPressComServiceRemote alloc] initWithApi:api];
        
        [service createWPComBlogWithUrl:[self getSiteAddressWithoutWordPressDotCom]
                           andBlogTitle:_siteTitleField.text
                          andLanguageId:languageId
                      andBlogVisibility:WordPressComServiceBlogVisibilityPublic
                                success:createBlogSuccess
                                failure:createBlogFailure];
    }];
    
    [blogCreation addDependency:siteValidation];
    
    [_operationQueue addOperation:siteValidation];
    [_operationQueue addOperation:blogCreation];
}

#pragma mark - Status bar management

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

@end
