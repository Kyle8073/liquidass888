#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"

static const void *kLGSpotlightOriginalTextTransformKey =
    &kLGSpotlightOriginalTextTransformKey;
static const void *kLGSpotlightSavedHiddenKey = &kLGSpotlightSavedHiddenKey;
static NSHashTable<UIView *> *sLGSpotlightBlurViews;
static NSHashTable<UIView *> *sLGSpotlightTextFields;

static void LGUpdateSpotlightTextField(UIView *view) {
    if (!sLGSpotlightTextFields)
        sLGSpotlightTextFields = [NSHashTable weakObjectsHashTable];
    [sLGSpotlightTextFields addObject:view];

    NSValue *original = objc_getAssociatedObject(
        view, kLGSpotlightOriginalTextTransformKey);
    if (!lgHostEnabled(@"Spotlight")) {
        if (original) {
            CGAffineTransform origTransform = original.CGAffineTransformValue;
            if (!CGAffineTransformEqualToTransform(view.transform, origTransform)) {
                view.transform = origTransform;
            }
            objc_setAssociatedObject(view,
                                     kLGSpotlightOriginalTextTransformKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    if (!view.window) return;
    if (!original) {
        original = [NSValue valueWithCGAffineTransform:view.transform];
        objc_setAssociatedObject(
            view, kLGSpotlightOriginalTextTransformKey, original,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGAffineTransform shifted = CGAffineTransformTranslate(
        original.CGAffineTransformValue, 0.0, -5.0);
    if (!CGAffineTransformEqualToTransform(view.transform, shifted)) {
        view.transform = shifted;
    }
}

static void LGUpdateSpotlightGlass(UIView *view) {
    if (!sLGSpotlightBlurViews)
        sLGSpotlightBlurViews = [NSHashTable weakObjectsHashTable];
    [sLGSpotlightBlurViews addObject:view];

    if (!lgHostEnabled(@"Spotlight") || !view.window || CGRectIsEmpty(view.bounds)) {
        LGRemoveGlassFromMaterial(view, kGlassKey);
        NSNumber *savedHidden = objc_getAssociatedObject(view, kLGSpotlightSavedHiddenKey);
        if (savedHidden) {
            objc_setAssociatedObject(view, kLGSpotlightSavedHiddenKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            view.hidden = savedHidden.boolValue;
        }
        return;
    }
    CGFloat radius = CGRectGetHeight(view.bounds) * 0.5;
    LGInstallRegisteredGlassInMaterial(view, kGlassKey, @"Spotlight",
                                       UIEdgeInsetsZero, radius, nil);
}

%group LGSpotlightHooks

%hook SPUIHeaderBlurView

- (void)didMoveToWindow {
    %orig;
    LGUpdateSpotlightGlass((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    LGUpdateSpotlightGlass((UIView *)self);
}

- (void)setHidden:(BOOL)hidden {
    UIView *self_ = (UIView *)self;
    if (LGMaterialHasGlass(self_, kGlassKey)) {
        objc_setAssociatedObject(self_, kLGSpotlightSavedHiddenKey, @(hidden),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        hidden = YES;
    }
    %orig(hidden);
}

%end

%hook SPUITextField

- (void)didMoveToWindow {
    %orig;
    LGUpdateSpotlightTextField((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    LGUpdateSpotlightTextField((UIView *)self);
}

%end

%end

%ctor {
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:
            (NSOperatingSystemVersion){16, 0, 0}]) {
        %init(LGSpotlightHooks);
        lgObservePreferenceReload(^{
            for (UIView *blurView in [sLGSpotlightBlurViews allObjects]) {
                LGUpdateSpotlightGlass(blurView);
            }
            for (UIView *field in [sLGSpotlightTextFields allObjects]) {
                LGUpdateSpotlightTextField(field);
            }
        });
    }
}
