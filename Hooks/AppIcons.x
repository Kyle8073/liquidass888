#import <UIKit/UIKit.h>
#import <math.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

static void *kLGAppIconGlassKey = &kLGAppIconGlassKey;
static NSHashTable<UIView *> *sLGAppIconViews;

static BOOL LGIsAppIconImageView(UIView *view) {
    if (!view || !isExactClass(view, @"SBIconImageView")) return NO;
    CGFloat w = CGRectGetWidth(view.bounds);
    CGFloat h = CGRectGetHeight(view.bounds);
    if (w < 48.0 || w > 110.0 || fabs(w - h) > 1.5) return NO;

    UIView *parent = view.superview;
    UIView *grandparent = parent.superview;
    static Class sIconViewClass = Nil;
    if (!sIconViewClass) sIconViewClass = NSClassFromString(@"SBIconView");
    return sIconViewClass && grandparent && [grandparent isKindOfClass:sIconViewClass];
}

static void LGRemoveAppIconGlass(UIView *iconView) {
    LGLiveBackdropView *glass = objc_getAssociatedObject(iconView, kLGAppIconGlassKey);
    [glass removeFromSuperview];
    objc_setAssociatedObject(iconView, kLGAppIconGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void LGInstallAppIconGlass(UIView *iconView) {
    if (!LGIsAppIconImageView(iconView) || !iconView.window ||
        !lgHostEnabled(@"AppIcons")) {
        LGRemoveAppIconGlass(iconView);
        return;
    }

    UIView *parent = iconView.superview;
    if (!parent) return;

    if (!sLGAppIconViews) sLGAppIconViews = [NSHashTable weakObjectsHashTable];
    [sLGAppIconViews addObject:iconView];

    LGLiveBackdropView *glass = objc_getAssociatedObject(iconView, kLGAppIconGlassKey);
    if (!glass) {
        glass = LGCreateRegisteredGlass(iconView.bounds, nil, @"AppIcons");
        if (!glass) return;
        glass.userInteractionEnabled = NO;
        glass.autoresizingMask = UIViewAutoresizingNone;
        objc_setAssociatedObject(iconView, kLGAppIconGlassKey,
                                 glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (glass.superview != parent) {
        [parent insertSubview:glass belowSubview:iconView];
    } else {
        NSArray<UIView *> *subs = parent.subviews;
        NSUInteger glassIdx = [subs indexOfObjectIdenticalTo:glass];
        NSUInteger iconIdx = [subs indexOfObjectIdenticalTo:iconView];
        if (glassIdx == NSNotFound || iconIdx == NSNotFound || glassIdx + 1 != iconIdx) {
            // the source icon stays visible above its glass underlay
            [parent insertSubview:glass belowSubview:iconView];
        }
    }

    if (!CGRectEqualToRect(glass.bounds, iconView.bounds)) glass.bounds = iconView.bounds;
    if (!CGPointEqualToPoint(glass.center, iconView.center)) glass.center = iconView.center;
    if (!CGAffineTransformEqualToTransform(glass.transform, iconView.transform)) {
        glass.transform = iconView.transform;
    }

    CGFloat iconRadius = iconView.layer.cornerRadius;
    CGFloat radius = (iconRadius > 0.5) ? iconRadius : (CGRectGetWidth(iconView.bounds) * 0.225);
    if (fabs(glass.layer.cornerRadius - radius) > 0.01) {
        glass.layer.cornerRadius = radius;
    }
    if (@available(iOS 13.0, *)) {
        if (glass.layer.cornerCurve != kCACornerCurveContinuous) {
            glass.layer.cornerCurve = kCACornerCurveContinuous;
        }
    }
    if (!glass.layer.masksToBounds) glass.layer.masksToBounds = YES;
    lgTrackGlass(glass, @"AppIcons", nil);
}

%hook SBIconImageView

- (void)didMoveToWindow {
    %orig;
    LGInstallAppIconGlass((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    LGInstallAppIconGlass((UIView *)self);
}

%end

%ctor {
    %init;
    lgObservePreferenceReload(^{
        for (UIView *iconView in [sLGAppIconViews allObjects]) {
            LGInstallAppIconGlass(iconView);
        }
    });
}
