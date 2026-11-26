#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"

@interface MTMaterialView : UIView
@end

@interface SBRingerPillView : UIView
@end

static const void * const kLGPillHUDGlassKey = &kLGPillHUDGlassKey;
static const void * const kLGPillHUDSavedHiddenKey = &kLGPillHUDSavedHiddenKey;
static const void * const kLGPillHUDSavedRadiusKey = &kLGPillHUDSavedRadiusKey;
static const void * const kLGPillHUDSavedCurveKey = &kLGPillHUDSavedCurveKey;
static NSHashTable<SBRingerPillView *> *sLGPillHUDViews;

static BOOL LGPillHUDEnabled(void) {
    return lgHostEnabled(@"PillHUD");
}

static void LGUpdateRingerPillGlass(SBRingerPillView *self) {
    if (!self) return;
    if (!sLGPillHUDViews) sLGPillHUDViews = [NSHashTable weakObjectsHashTable];
    [sLGPillHUDViews addObject:self];

    MTMaterialView *base = nil;
    UIView *shadow = nil;
    @try {
        base = [self valueForKey:@"_materialView"];
        shadow = [self valueForKey:@"_shadowView"];
    } @catch (...) {}

    LGLiveBackdropView *glass = objc_getAssociatedObject(self, kLGPillHUDGlassKey);
    if (!LGPillHUDEnabled()) {
        if (glass) {
            [glass removeFromSuperview];
            objc_setAssociatedObject(self, kLGPillHUDGlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
        if (base) {
            NSNumber *savedHidden = objc_getAssociatedObject(base, kLGPillHUDSavedHiddenKey);
            if (savedHidden) {
                base.hidden = savedHidden.boolValue;
                objc_setAssociatedObject(base, kLGPillHUDSavedHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
            }
        }
        NSNumber *savedRadius = objc_getAssociatedObject(self, kLGPillHUDSavedRadiusKey);
        if (savedRadius) {
            self.layer.cornerRadius = savedRadius.doubleValue;
            if (@available(iOS 13.0, *)) {
                CALayerCornerCurve curve = objc_getAssociatedObject(self, kLGPillHUDSavedCurveKey);
                if (curve) self.layer.cornerCurve = curve;
            }
            objc_setAssociatedObject(self, kLGPillHUDSavedRadiusKey, nil, OBJC_ASSOCIATION_ASSIGN);
            objc_setAssociatedObject(self, kLGPillHUDSavedCurveKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
        return;
    }

    if (!self.window || CGRectIsEmpty(self.bounds)) return;

    if (base) {
        if (!objc_getAssociatedObject(base, kLGPillHUDSavedHiddenKey)) {
            objc_setAssociatedObject(base, kLGPillHUDSavedHiddenKey, @(base.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        base.hidden = YES;
    }
    BOOL freshInject = NO;
    if (!glass) {
        glass = LGCreateRegisteredGlass(self.bounds, nil, @"PillHUD");
        if (!glass) return;
        objc_setAssociatedObject(self, kLGPillHUDGlassKey, glass,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        lgTrackGlass(glass, @"PillHUD", nil);
        if (shadow) [self insertSubview:glass aboveSubview:shadow];
        else [self insertSubview:glass atIndex:0];
        freshInject = YES;
    }

    CGFloat radius = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds)) * 0.5;
    glass.hidden = NO;
    if (!CGRectEqualToRect(glass.frame, self.bounds)) glass.frame = self.bounds;
    glass.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.masksToBounds = YES;
    if (freshInject) [glass applyFilters];

    if (!objc_getAssociatedObject(self, kLGPillHUDSavedRadiusKey)) {
        objc_setAssociatedObject(self, kLGPillHUDSavedRadiusKey, @(self.layer.cornerRadius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (@available(iOS 13.0, *)) {
            objc_setAssociatedObject(self, kLGPillHUDSavedCurveKey, self.layer.cornerCurve ?: kCACornerCurveCircular, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    }
    self.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) self.layer.cornerCurve = kCACornerCurveContinuous;
}

%group LGPillHUDHooks

%hook SBRingerPillView

- (void)didMoveToWindow {
    %orig;
    LGUpdateRingerPillGlass(self);
}

- (void)layoutSubviews {
    %orig;
    LGUpdateRingerPillGlass(self);
}

%end

%end

%ctor {
    if (!LGIsSpringBoardProcess() || !NSClassFromString(@"SBRingerPillView")) return;
    %init(LGPillHUDHooks);
    lgObservePreferenceReload(^{
        LGLog(@"PillHUD: Preferences reloaded");
        for (SBRingerPillView *pill in sLGPillHUDViews.allObjects) {
            LGUpdateRingerPillGlass(pill);
        }
    });
}
