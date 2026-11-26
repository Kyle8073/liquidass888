#import <UIKit/UIKit.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"
#import <objc/runtime.h>

typedef struct {
    NSUInteger calls;
    CFTimeInterval total;
    CFTimeInterval peak;
    CFTimeInterval started;
} LGNotificationProfile;

static LGNotificationProfile sLGNotificationProfile;

static void LGNotificationProfileSample(CFTimeInterval elapsed) {
    if (!LGDebugLoggingEnabled()) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (sLGNotificationProfile.started == 0.0) sLGNotificationProfile.started = now;
    sLGNotificationProfile.calls++;
    sLGNotificationProfile.total += elapsed;
    sLGNotificationProfile.peak = MAX(sLGNotificationProfile.peak, elapsed);
    if (now - sLGNotificationProfile.started < 1.0) return;
    LGLog(@"[NOTIFPROF] materialUpdates=%lu avg=%.3fms total=%.3fms peak=%.3fms",
          (unsigned long)sLGNotificationProfile.calls,
          sLGNotificationProfile.total * 1000.0 / MAX((NSUInteger)1, sLGNotificationProfile.calls),
          sLGNotificationProfile.total * 1000.0,
          sLGNotificationProfile.peak * 1000.0);
    sLGNotificationProfile = (LGNotificationProfile){ .started = now };
}

static BOOL LGHasMaterialAncestorBefore(UIView *material, NSString *stopClassName) {
    Class stopCls = NSClassFromString(stopClassName);
    static Class materialClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ materialClass = NSClassFromString(@"MTMaterialView"); });
    for (UIView *v = material.superview; v; v = v.superview) {
        if (stopCls && [v isKindOfClass:stopCls]) return NO;
        if (materialClass && [v isKindOfClass:materialClass]) return YES;
    }
    return NO;
}

static BOOL LGIsPlatterMaterial(UIView *material) {
    if (!hasAncestorOfClassName(material, @"PLPlatterView")) return NO;
    if (hasAncestorOfClassName(material, @"SBSwitcherAppSuggestionBannerView")) return NO;
    return !LGHasMaterialAncestorBefore(material, @"PLPlatterView");
}

static UIView *LGPlatterActionButtonAncestor(UIView *material) {
    static Class materialClass;
    static Class platterActionClass;
    static Class notifActionClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        materialClass = NSClassFromString(@"MTMaterialView");
        platterActionClass = NSClassFromString(@"PLPlatterActionButton");
        notifActionClass = NSClassFromString(@"NCNotificationListCellActionButton");
    });
    for (UIView *v = material.superview; v; v = v.superview) {
        if ((platterActionClass && [v isKindOfClass:platterActionClass]) ||
            (notifActionClass && [v isKindOfClass:notifActionClass]))
            return v;
        if (materialClass && [v isKindOfClass:materialClass]) return nil;
    }
    return nil;
}

static BOOL LGIsPlatterActionMaterial(UIView *material) {
    if (hasAncestorOfClassName(material, @"SBSwitcherAppSuggestionBannerView")) return NO;
    return LGPlatterActionButtonAncestor(material) != nil;
}

static BOOL LGResponderChainContainsClass(UIResponder *responder, Class cls) {
    if (!cls) return NO;
    for (UIResponder *r = responder; r; r = r.nextResponder)
        if ([r isKindOfClass:cls]) return YES;
    return NO;
}

static void *kLGPlatterClassificationKey = &kLGPlatterClassificationKey;
static void *kLGLabelOriginalColorKey = &kLGLabelOriginalColorKey;
static void *kLGLabelApplyingColorKey = &kLGLabelApplyingColorKey;
static NSHashTable<UILabel *> *sLGBannerLabels;
static NSHashTable *sLGBannerNotificationControllers;

static BOOL LGIsTopBannerPresentation(UIView *view) {
    if (!view.window) return NO;
    static Class bannerWindowCls;
    static Class bnContentViewCls;
    static Class bnControllerCls;
    static Class sbPresentableCls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bannerWindowCls = NSClassFromString(@"SBBannerWindow");
        bnContentViewCls = NSClassFromString(@"BNContentViewControllerView");
        bnControllerCls = NSClassFromString(@"BNContentViewController");
        sbPresentableCls = NSClassFromString(@"SBNotificationPresentableViewController");
    });
    if (bannerWindowCls && [view.window isKindOfClass:bannerWindowCls]) return YES;
    if (bnContentViewCls && hasAncestorOfClassName(view, @"BNContentViewControllerView")) return YES;
    if (LGResponderChainContainsClass(view, bnControllerCls)) return YES;
    return LGResponderChainContainsClass(view, sbPresentableCls);
}

static UIView *LGNotificationAncestor(UIView *view) {
    if (hasAncestorOfClassName(view, @"SBSwitcherAppSuggestionBannerView")) return nil;
    static Class shortLookCls;
    static Class longLookCls;
    static Class platterCls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shortLookCls = NSClassFromString(@"NCNotificationShortLookView");
        longLookCls = NSClassFromString(@"NCNotificationLongLookView");
        platterCls = NSClassFromString(@"PLPlatterView");
    });
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if ((shortLookCls && [ancestor isKindOfClass:shortLookCls]) ||
            (longLookCls && [ancestor isKindOfClass:longLookCls]) ||
            (platterCls && [ancestor isKindOfClass:platterCls])) return ancestor;
    }
    return nil;
}

static UIColor *LGForcedPlatterTextColor(UIView *view) {
    if (!view || !view.window) return nil;
    BOOL bannerOn = lgHostEnabled(@"Banner");
    BOOL notifOn = lgHostEnabled(@"Notification");
    if (!bannerOn && !notifOn) return nil;
    if (LGIsTopBannerPresentation(view))
        return bannerOn &&
               view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight
            ? UIColor.blackColor : nil;
    if (!notifOn || !LGNotificationAncestor(view)) return nil;
    return [LGGlassPreferenceValue(@"Notification.LabelColor") isEqual:@"black"]
        ? UIColor.blackColor : UIColor.whiteColor;
}

static NSAttributedString *LGAttributedTextWithColor(NSAttributedString *text, UIColor *color) {
    if (!color || !text.length) return text;
    NSMutableAttributedString *copy = [text mutableCopy];
    [copy addAttribute:NSForegroundColorAttributeName
                 value:color
                 range:NSMakeRange(0, copy.length)];
    return copy;
}

static void LGRefreshLabelPlatterColor(UILabel *label) {
    if (!label) return;
    UIColor *forced = LGForcedPlatterTextColor(label);
    UIColor *saved = objc_getAssociatedObject(label, kLGLabelOriginalColorKey);
    if (!forced && !saved) return;
    if (forced && !saved && label.textColor) {
        objc_setAssociatedObject(label, kLGLabelOriginalColorKey, label.textColor,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIColor *target = forced ?: saved;
    if (!target) return;
    objc_setAssociatedObject(label, kLGLabelApplyingColorKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (label.attributedText.length) {
        label.attributedText = LGAttributedTextWithColor(label.attributedText, target);
    }
    label.textColor = target;
    objc_setAssociatedObject(label, kLGLabelApplyingColorKey, nil, OBJC_ASSOCIATION_ASSIGN);
    if (!forced) {
        objc_setAssociatedObject(label, kLGLabelOriginalColorKey, nil, OBJC_ASSOCIATION_ASSIGN);
    } else {
        if (!sLGBannerLabels) sLGBannerLabels = [NSHashTable weakObjectsHashTable];
        [sLGBannerLabels addObject:label];
    }
}

static void LGDisableLockscreenStackDimming(id controller) {
    if (!controller) return;
    if (!sLGBannerNotificationControllers) {
        sLGBannerNotificationControllers = [NSHashTable weakObjectsHashTable];
    }
    [sLGBannerNotificationControllers addObject:controller];
    // stack dimming belongs to notifications and not top banners
    if (LGIsTopBannerPresentation([controller isKindOfClass:[UIViewController class]]
                                  ? ((UIViewController *)controller).viewIfLoaded : nil)) return;
    @try {
        id preview = [controller valueForKey:@"viewForPreview"];
        UIView *dimming = [preview valueForKey:@"stackDimmingOverlayView"];
        if (!dimming) {
            id contentSizeManager = [controller valueForKey:@"contentSizeManagingView"];
            dimming = [contentSizeManager valueForKey:@"stackDimmingView"];
        }
        if (dimming) dimming.hidden = lgHostEnabled(@"Notification");
    } @catch (__unused NSException *exception) {

    }
}

static CGFloat LGActionButtonRadius(UIView *material) {
    UIView *button = LGPlatterActionButtonAncestor(material) ?: material;
    if (button.layer.cornerRadius > 0.5) return button.layer.cornerRadius;
    if (material.layer.cornerRadius > 0.5) return material.layer.cornerRadius;
    return CGRectGetHeight(button.bounds) * 0.5;
}

static void LGUpdatePlatterGlass(UIView *material) {
    // one platter class serves banners notifications and action buttons

    if (!material.window) return;
    CFTimeInterval start = CACurrentMediaTime();

    if (LGIsPlatterMaterial(material)) {
        BOOL topBanner = LGIsTopBannerPresentation(material);
        NSString *prefix = topBanner ? @"Banner" : @"Notification";
        NSString *previous = objc_getAssociatedObject(material, kLGPlatterClassificationKey);
        if (previous && ![previous isEqualToString:prefix]) {
            LGRemoveGlassFromMaterial(material, kGlassKey);
        }
        if (![previous isEqualToString:prefix]) {
            objc_setAssociatedObject(material, kLGPlatterClassificationKey, prefix,
                                     OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
        LGInstallRegisteredGlassInMaterial(material, kGlassKey, prefix,
                                           UIEdgeInsetsZero, -1.0, nil);
    } else if (LGIsPlatterActionMaterial(material)) {
        NSString *actionPrefix = LGIsTopBannerPresentation(material) ? @"Banner" : @"Notification";
        LGInstallRegisteredGlassInMaterial(material, kGlassKey, actionPrefix,
                                           UIEdgeInsetsZero,
                                           LGActionButtonRadius(material), nil);
    }
    LGNotificationProfileSample(CACurrentMediaTime() - start);
}

%hook MTMaterialView
- (void)didMoveToWindow {
    %orig;
    UIView *self_ = (UIView *)self;
    if (self_.window) LGUpdatePlatterGlass(self_);
}
- (void)layoutSubviews {
    %orig;
    LGUpdatePlatterGlass((UIView *)self);
}
%end

%hook UILabel
- (void)setTextColor:(UIColor *)color {
    if (![objc_getAssociatedObject(self, kLGLabelApplyingColorKey) boolValue]) {
        UIColor *forced = LGForcedPlatterTextColor((UIView *)self);
        if (forced) {
            if (color) {
                objc_setAssociatedObject(self, kLGLabelOriginalColorKey, color,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (!sLGBannerLabels) sLGBannerLabels = [NSHashTable weakObjectsHashTable];
            [sLGBannerLabels addObject:(UILabel *)self];
            color = forced;
        } else if (color) {
            objc_setAssociatedObject(self, kLGLabelOriginalColorKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
    }
    %orig(color);
}
- (void)setAttributedText:(NSAttributedString *)text {
    if (![objc_getAssociatedObject(self, kLGLabelApplyingColorKey) boolValue]) {
        UIColor *forced = LGForcedPlatterTextColor((UIView *)self);
        if (forced) {
            if (!objc_getAssociatedObject(self, kLGLabelOriginalColorKey) && self.textColor) {
                objc_setAssociatedObject(self, kLGLabelOriginalColorKey, self.textColor,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (!sLGBannerLabels) sLGBannerLabels = [NSHashTable weakObjectsHashTable];
            [sLGBannerLabels addObject:(UILabel *)self];
            text = LGAttributedTextWithColor(text, forced);
        }
    }
    %orig(text);
}
- (void)didMoveToWindow {
    %orig;
    LGRefreshLabelPlatterColor((UILabel *)self);
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig(previousTraitCollection);
    LGRefreshLabelPlatterColor((UILabel *)self);
}
%end

%hook NCNotificationShortLookViewController
- (void)viewDidLoad {
    %orig;
    LGDisableLockscreenStackDimming(self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    LGDisableLockscreenStackDimming(self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    LGDisableLockscreenStackDimming(self);
}
%end

%ctor {
    lgObservePreferenceReload(^{
        for (UILabel *label in sLGBannerLabels.allObjects) {
            LGRefreshLabelPlatterColor(label);
        }
        for (id controller in sLGBannerNotificationControllers.allObjects) {
            LGDisableLockscreenStackDimming(controller);
        }
    });
}
