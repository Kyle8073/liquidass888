#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

static const CGFloat kWidgetCornerRadius = 20.2;
static void *kWidgetGlassKey = &kWidgetGlassKey;
static void *kWidgetSavedCornerKey = &kWidgetSavedCornerKey;
static void *kWidgetSavedHiddenKey = &kWidgetSavedHiddenKey;

static NSHashTable<UIView *> *sWidgetContainerHosts;
static NSHashTable<UIView *> *sWidgetStackMaterials;

static Class sWidgetStackVCClass = Nil;
static Class sTouchPassThroughClass = Nil;
static Class sWidgetIconViewClass = Nil;
static Class sBSUIScrollViewClass = Nil;
static Class sWidgetContainerViewClass = Nil;
static Class sWidgetMTMaterialClass = Nil;

static void widgetEnsureClasses(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sWidgetStackVCClass = NSClassFromString(@"SBHWidgetStackViewController");
        sTouchPassThroughClass = NSClassFromString(@"SBFTouchPassThroughView");
        sWidgetIconViewClass = NSClassFromString(@"SBIconView");
        sBSUIScrollViewClass = NSClassFromString(@"BSUIScrollView");
        sWidgetContainerViewClass = NSClassFromString(@"SBHWidgetContainerView");
        sWidgetMTMaterialClass = NSClassFromString(@"MTMaterialView");
    });
}

@interface CHSWidget : NSObject
@property (nonatomic, copy, readonly) NSString *extensionBundleIdentifier;
@end

@interface CHUISWidgetHostViewController : UIViewController
@property (nonatomic, copy) CHSWidget *widget;
@end

@interface CHUISAvocadoHostViewController : UIViewController
@property (nonatomic, copy) CHSWidget *widget;
@end

static UIViewController *widgetNearestStackController(UIView *view) {
    widgetEnsureClasses();
    if (!sWidgetStackVCClass) return nil;
    for (UIResponder *r = view; r; r = r.nextResponder)
        if ([r isKindOfClass:sWidgetStackVCClass] && [r isKindOfClass:[UIViewController class]])
            return (UIViewController *)r;
    return nil;
}

static BOOL widgetHasAncestorClassWithinDepth(UIView *view, Class targetClass, NSInteger maxDepth) {
    if (!targetClass) return NO;
    NSInteger depth = 0;
    for (UIView *a = view.superview; a && depth < maxDepth; a = a.superview, depth++)
        if ([a isKindOfClass:targetClass]) return YES;
    return NO;
}

static BOOL widgetSubtreeContainsClass(UIView *view, Class targetClass) {
    if (!targetClass) return NO;
    if ([view isKindOfClass:targetClass]) return YES;
    for (UIView *sub in view.subviews)
        if (widgetSubtreeContainsClass(sub, targetClass)) return YES;
    return NO;
}

static UIView *widgetFindDescendantClass(UIView *view, Class targetClass) {
    if (!targetClass) return nil;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:targetClass]) return sub;
        UIView *found = widgetFindDescendantClass(sub, targetClass);
        if (found) return found;
    }
    return nil;
}

static BOOL isWidgetGlassHostContainer(UIView *view) {
    // widget internals vary so use the nearest stable container
    widgetEnsureClasses();
    if (!isExactClass(view, @"UIView")) return NO;
    if (view.bounds.size.width < 120.0 || view.bounds.size.height < 120.0) return NO;
    if (!widgetNearestStackController(view)) return NO;
    if (!widgetHasAncestorClassWithinDepth(view, sTouchPassThroughClass, 8)) return NO;
    if (!widgetHasAncestorClassWithinDepth(view, sWidgetIconViewClass, 10)) return NO;
    for (UIView *sub in view.subviews) {
        if (!isExactClass(sub, @"UIView") && !(sBSUIScrollViewClass && [sub isKindOfClass:sBSUIScrollViewClass])) continue;
        UIView *scroll = (sBSUIScrollViewClass && [sub isKindOfClass:sBSUIScrollViewClass]) ? sub
                       : widgetFindDescendantClass(sub, sBSUIScrollViewClass);
        if (scroll && widgetSubtreeContainsClass(scroll, sWidgetContainerViewClass)) return YES;
    }
    return NO;
}

static UIView *widgetAncestorContainerHost(UIView *view) {
    NSInteger depth = 0;
    for (UIView *a = view; a && depth < 12; a = a.superview, depth++)
        if (isWidgetGlassHostContainer(a)) return a;
    return nil;
}

static BOOL isWidgetStackBackgroundMaterial(UIView *mat) {
    // stack backgrounds stay stock so child widgets keep separate lenses
    widgetEnsureClasses();
    if (!sWidgetMTMaterialClass || ![mat isMemberOfClass:sWidgetMTMaterialClass]) return NO;
    UIView *parent = mat.superview;
    if (!isExactClass(parent, @"UIView")) return NO;
    UIViewController *vc = widgetNearestStackController(parent);
    if (!vc) return NO;
    return vc.view == parent || parent.superview == vc.view;
}

static void removeWidgetGlass(UIView *container) {
    LGLiveBackdropView *glass = objc_getAssociatedObject(container, kWidgetGlassKey);
    if (!glass) return;
    [glass removeFromSuperview];
    objc_setAssociatedObject(container, kWidgetGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSDictionary *saved = objc_getAssociatedObject(container, kWidgetSavedCornerKey);
    if (saved) {
        objc_setAssociatedObject(container, kWidgetSavedCornerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        container.layer.cornerRadius = [saved[@"radius"] doubleValue];
        if (@available(iOS 13.0, *)) {
            NSString *curve = saved[@"curve"];
            if (curve.length) container.layer.cornerCurve = curve;
        }
        container.layer.masksToBounds = [saved[@"masks"] boolValue];
        container.clipsToBounds = [saved[@"clips"] boolValue];
    }
}

static void injectWidgetGlass(UIView *container) {
    if (!lgHostEnabled(@"Widgets") || !container.window || CGRectIsEmpty(container.bounds)) {
        removeWidgetGlass(container);
        return;
    }
    if (!sWidgetContainerHosts) sWidgetContainerHosts = [NSHashTable weakObjectsHashTable];
    [sWidgetContainerHosts addObject:container];

    if (!objc_getAssociatedObject(container, kWidgetSavedCornerKey)) {
        NSString *curve = @"";
        if (@available(iOS 13.0, *)) curve = container.layer.cornerCurve ?: @"";
        objc_setAssociatedObject(container, kWidgetSavedCornerKey, @{
            @"radius": @(container.layer.cornerRadius),
            @"curve": curve,
            @"masks": @(container.layer.masksToBounds),
            @"clips": @(container.clipsToBounds),
        }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    LGLiveBackdropView *glass = objc_getAssociatedObject(container, kWidgetGlassKey);
    BOOL fresh = (glass == nil);
    if (!glass) {
        glass = LGCreateRegisteredGlass(container.bounds, nil, @"Widgets");
        if (!glass) return;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [container insertSubview:glass atIndex:0];
        objc_setAssociatedObject(container, kWidgetGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glass.superview != container) [container insertSubview:glass atIndex:0];
    else if (container.subviews.firstObject != glass) [container sendSubviewToBack:glass];

    if (!CGRectEqualToRect(glass.frame, container.bounds)) glass.frame = container.bounds;
    if (fabs(glass.layer.cornerRadius - kWidgetCornerRadius) > 0.01) {
        glass.layer.cornerRadius = kWidgetCornerRadius;
    }
    if (@available(iOS 13.0, *)) {
        if (glass.layer.cornerCurve != kCACornerCurveContinuous) {
            glass.layer.cornerCurve = kCACornerCurveContinuous;
        }
    }
    if (!glass.layer.masksToBounds) glass.layer.masksToBounds = YES;
    if (fresh || !glass.lgFilterAttached) [glass applyFilters];

    if (fabs(container.layer.cornerRadius - kWidgetCornerRadius) > 0.01) {
        container.layer.cornerRadius = kWidgetCornerRadius;
    }
    if (@available(iOS 13.0, *)) {
        if (container.layer.cornerCurve != kCACornerCurveContinuous) {
            container.layer.cornerCurve = kCACornerCurveContinuous;
        }
    }
    if (!container.layer.masksToBounds) container.layer.masksToBounds = YES;
    if (!container.clipsToBounds) container.clipsToBounds = YES;
    lgTrackGlass(glass, @"Widgets", nil);
}

static void updateWidgetStackMaterial(UIView *mat) {
    if (!sWidgetStackMaterials) sWidgetStackMaterials = [NSHashTable weakObjectsHashTable];
    [sWidgetStackMaterials addObject:mat];

    if (mat.window && lgHostEnabled(@"Widgets")) {
        if (!objc_getAssociatedObject(mat, kWidgetSavedHiddenKey)) {
            objc_setAssociatedObject(mat, kWidgetSavedHiddenKey, @(mat.hidden),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        lgSuppressStock(mat, @"Widgets", YES);
    } else {
        NSNumber *savedHidden = objc_getAssociatedObject(mat, kWidgetSavedHiddenKey);
        if (savedHidden) {
            objc_setAssociatedObject(mat, kWidgetSavedHiddenKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            mat.hidden = savedHidden.boolValue;
            mat.alpha = 1.0;
        }
    }
}

#pragma mark - hooks

%hook MTMaterialView
- (void)didMoveToWindow {
    %orig;
    UIView *self_ = (UIView *)self;
    if (isWidgetStackBackgroundMaterial(self_)) {
        updateWidgetStackMaterial(self_);
    }
}
- (void)layoutSubviews {
    %orig;
    UIView *self_ = (UIView *)self;
    if (isWidgetStackBackgroundMaterial(self_)) {
        updateWidgetStackMaterial(self_);
    }
}
- (void)setHidden:(BOOL)hidden {
    UIView *self_ = (UIView *)self;
    if (lgHostEnabled(@"Widgets") && isWidgetStackBackgroundMaterial(self_)) {
        objc_setAssociatedObject(self_, kWidgetSavedHiddenKey, @(hidden),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        hidden = YES;
        lgSuppressStock(self_, @"Widgets", NO);
    }
    %orig(hidden);
}
%end

%hook CHUISAvocadoHostViewController
- (void)_updateBackgroundMaterialAndColor {
    if (lgHostEnabled(@"Widgets") && self.widget.extensionBundleIdentifier.length) return;
    %orig;
}
- (id)screenshotManager {
    if (lgHostEnabled(@"Widgets") && self.widget.extensionBundleIdentifier.length) return nil;
    return %orig;
}
%end

%hook CHUISWidgetHostViewController
- (void)_updateBackgroundMaterialAndColor {
    if (lgHostEnabled(@"Widgets") && self.widget.extensionBundleIdentifier.length) return;
    %orig;
}
- (void)_updatePersistedSnapshotContent {
    if (lgHostEnabled(@"Widgets") && self.widget.extensionBundleIdentifier.length) return;
    %orig;
}
- (void)_updatePersistedSnapshotContentIfNecessary {
    if (lgHostEnabled(@"Widgets") && self.widget.extensionBundleIdentifier.length) return;
    %orig;
}
- (id)_snapshotImageFromURL:(id)arg1 {
    if (lgHostEnabled(@"Widgets") && self.widget.extensionBundleIdentifier.length) return nil;
    return %orig;
}
%end

%hook BSUIScrollView
- (void)didMoveToWindow {
    %orig;
    UIView *self_ = (UIView *)self;
    if (!lgHostEnabled(@"Widgets") && !sWidgetContainerHosts.count) return;
    UIView *host = widgetAncestorContainerHost(self_);
    if (!host) return;
    if (!self_.window) { removeWidgetGlass(host); return; }
    injectWidgetGlass(host);
}
- (void)layoutSubviews {
    %orig;
    UIView *self_ = (UIView *)self;
    if (!self_.window) return;
    if (!lgHostEnabled(@"Widgets") && !sWidgetContainerHosts.count) return;
    UIView *host = widgetAncestorContainerHost(self_);
    if (host) injectWidgetGlass(host);
}
%end

%ctor {
    %init;
    lgObservePreferenceReload(^{
        for (UIView *host in [sWidgetContainerHosts allObjects]) {
            injectWidgetGlass(host);
        }
        for (UIView *mat in [sWidgetStackMaterials allObjects]) {
            updateWidgetStackMaterial(mat);
        }
    });
}
