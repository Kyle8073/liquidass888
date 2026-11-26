#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"

@interface MTMaterialView : UIView
@end

@interface CCUIContinuousSliderView : UIControl
@end

@interface SBElasticSliderView : CCUIContinuousSliderView
@end

@interface SBElasticVolumeSliderView : SBElasticSliderView
@end

@interface SBElasticSliderMaterialWrapperView : UIView {
    MTMaterialView *_captureOnlyMaterialView;
    MTMaterialView *_baseMaterialView;
    UIView *_shadowView;
    UIView *_sliderWrapperView;
    UIView *_maskView;
    SBElasticVolumeSliderView *_sliderView;
}
- (void)_setContinuousCornerRadius:(double)radius;
@end

@interface LGVolumeHUDVibranceView : UIView
@end

@implementation LGVolumeHUDVibranceView

+ (Class)layerClass {
    return NSClassFromString(@"CABackdropLayer") ?: [CALayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingNone;
        [self applyVibranceFilters];
    }
    return self;
}

- (void)applyVibranceFilters {
    @try {
        CALayer *layer = self.layer;
        Class backdropCls = NSClassFromString(@"CABackdropLayer");
        if (!backdropCls || ![layer isKindOfClass:backdropCls]) return;

        [layer setValue:@(0.5) forKey:@"scale"];
        if (layer.filters.count > 0) return;

        Class filterCls = NSClassFromString(@"CAFilter");
        if (!filterCls) return;

        NSMutableArray *filters = [NSMutableArray array];

        id satFilter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
            filterCls, NSSelectorFromString(@"filterWithType:"), @"colorSaturate");
        if (satFilter) {
            @try { [satFilter setValue:@(1.85) forKey:@"inputAmount"]; } @catch (...) {}
            [filters addObject:satFilter];
        }

        id contrastFilter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
            filterCls, NSSelectorFromString(@"filterWithType:"), @"colorContrast");
        if (contrastFilter) {
            @try { [contrastFilter setValue:@(1.06) forKey:@"inputAmount"]; } @catch (...) {}
            [filters addObject:contrastFilter];
        }

        layer.filters = filters;
    } @catch (NSException *e) {}
}

@end

static const void * const kLGVolumeHUDGlassKey = &kLGVolumeHUDGlassKey;
static const void * const kLGVolumeHUDVibranceKey = &kLGVolumeHUDVibranceKey;
static const void * const kLGVolumeHUDMaterialHiddenKey = &kLGVolumeHUDMaterialHiddenKey;
static const void * const kLGVolumeHUDProbePendingKey = &kLGVolumeHUDProbePendingKey;
static const void * const kLGVolumeHUDSavedHiddenKey = &kLGVolumeHUDSavedHiddenKey;
static const void * const kLGVolumeHUDSavedRadiusKey = &kLGVolumeHUDSavedRadiusKey;
static const void * const kLGVolumeHUDSavedCurveKey = &kLGVolumeHUDSavedCurveKey;
static const void * const kLGVolumeHUDSavedMasksKey = &kLGVolumeHUDSavedMasksKey;
static NSHashTable<SBElasticSliderMaterialWrapperView *> *sLGVolumeHUDWrappers;

static void LGVolumeHUDSaveAndHide(UIView *view) {
    if (!view) return;
    if (!objc_getAssociatedObject(view, kLGVolumeHUDSavedHiddenKey)) {
        objc_setAssociatedObject(view, kLGVolumeHUDSavedHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    view.hidden = YES;
}

static void LGVolumeHUDRestoreHidden(UIView *view) {
    if (!view) return;
    NSNumber *saved = objc_getAssociatedObject(view, kLGVolumeHUDSavedHiddenKey);
    if (saved) {
        view.hidden = saved.boolValue;
        objc_setAssociatedObject(view, kLGVolumeHUDSavedHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
}

static void LGVolumeHUDSaveLayer(UIView *view) {
    if (!view || objc_getAssociatedObject(view, kLGVolumeHUDSavedRadiusKey)) return;
    objc_setAssociatedObject(view, kLGVolumeHUDSavedRadiusKey, @(view.layer.cornerRadius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (@available(iOS 13.0, *)) {
        objc_setAssociatedObject(view, kLGVolumeHUDSavedCurveKey, view.layer.cornerCurve ?: kCACornerCurveCircular, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    objc_setAssociatedObject(view, kLGVolumeHUDSavedMasksKey, @(view.layer.masksToBounds), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void LGVolumeHUDRestoreLayer(UIView *view) {
    if (!view) return;
    NSNumber *radius = objc_getAssociatedObject(view, kLGVolumeHUDSavedRadiusKey);
    if (!radius) return;
    view.layer.cornerRadius = radius.doubleValue;
    if (@available(iOS 13.0, *)) {
        CALayerCornerCurve curve = objc_getAssociatedObject(view, kLGVolumeHUDSavedCurveKey);
        if (curve) view.layer.cornerCurve = curve;
    }
    NSNumber *masks = objc_getAssociatedObject(view, kLGVolumeHUDSavedMasksKey);
    if (masks) view.layer.masksToBounds = masks.boolValue;
    objc_setAssociatedObject(view, kLGVolumeHUDSavedRadiusKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(view, kLGVolumeHUDSavedCurveKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(view, kLGVolumeHUDSavedMasksKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static BOOL LGVolumeHUDEnabled(void) {
    return lgHostEnabled(@"VolumeHUD");
}

static BOOL LGVolumeHUDNeedsLegacyMaterialWorkaround(void) {
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 16;
}

static UIView *LGVolumeHUDDescendant(UIView *view, Class targetClass) {
    if ([view isKindOfClass:targetClass]) return view;
    for (UIView *subview in view.subviews) {
        UIView *found = LGVolumeHUDDescendant(subview, targetClass);
        if (found) return found;
    }
    return nil;
}

static void LGSetVolumeHUDBackgroundMaterialsHidden(UIView *view, BOOL hidden) {
    if ([view isKindOfClass:NSClassFromString(@"MTMaterialView")] &&
        [view.superview isKindOfClass:NSClassFromString(@"MTMaterialShadowView")]) {
        NSNumber *original = objc_getAssociatedObject(view, kLGVolumeHUDMaterialHiddenKey);
        if (hidden) {
            if (!original)
                objc_setAssociatedObject(view, kLGVolumeHUDMaterialHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            view.hidden = YES;
        } else if (original) {
            view.hidden = original.boolValue;
            objc_setAssociatedObject(view, kLGVolumeHUDMaterialHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
    }
    for (UIView *subview in view.subviews) LGSetVolumeHUDBackgroundMaterialsHidden(subview, hidden);
}

static void LGAppendVolumeHUDMaterialRows(UIView *view, NSString *path,
                                          NSMutableArray<NSString *> *rows) {
    NSString *nextPath = [path stringByAppendingFormat:@"/%@", NSStringFromClass(view.class)];
    if ([view isKindOfClass:NSClassFromString(@"MTMaterialView")])
        [rows addObject:[NSString stringWithFormat:@"%@ frame=%@ hidden=%d alpha=%.2f radius=%.2f",
            nextPath, NSStringFromCGRect(view.frame), view.hidden, view.alpha, view.layer.cornerRadius]];
    for (UIView *subview in view.subviews) LGAppendVolumeHUDMaterialRows(subview, nextPath, rows);
}

static void LGScheduleVolumeHUDProbe(UIView *wrapper) {
    if (!LGDebugLoggingEnabled() || [objc_getAssociatedObject(wrapper, kLGVolumeHUDProbePendingKey) boolValue]) return;
    objc_setAssociatedObject(wrapper, kLGVolumeHUDProbePendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(wrapper, kLGVolumeHUDProbePendingKey, nil, OBJC_ASSOCIATION_ASSIGN);
        if (!wrapper.window) return;
        NSMutableArray<NSString *> *rows = [NSMutableArray array];
        LGAppendVolumeHUDMaterialRows(wrapper, @"", rows);
        LGLog(@"[VolumeHUD probe] wrapper=%@ bounds=%@ materials=[%@]",
              NSStringFromClass(wrapper.class), NSStringFromCGRect(wrapper.bounds),
              [rows componentsJoinedByString:@" | "]);
    });
}

static void LGUpdateVolumeHUDGlass(SBElasticSliderMaterialWrapperView *self) {
    if (!self) return;
    if (!sLGVolumeHUDWrappers) sLGVolumeHUDWrappers = [NSHashTable weakObjectsHashTable];
    [sLGVolumeHUDWrappers addObject:self];

    MTMaterialView *base = nil;
    MTMaterialView *cap = nil;
    UIView *shadow = nil;
    UIView *sliderWrapper = nil;
    UIView *sliderView = nil;
    @try {
        base = [self valueForKey:@"_baseMaterialView"];
        cap = [self valueForKey:@"_captureOnlyMaterialView"];
        shadow = [self valueForKey:@"_shadowView"];
        sliderWrapper = [self valueForKey:@"_sliderWrapperView"];
        sliderView = [self valueForKey:@"_sliderView"];
    } @catch (...) {}
    if (!sliderView)
        sliderView = LGVolumeHUDDescendant(self, NSClassFromString(@"SBElasticVolumeSliderView"));

    if (!LGVolumeHUDEnabled()) {
        LGLiveBackdropView *existing = objc_getAssociatedObject(self, kLGVolumeHUDGlassKey);
        if (existing) {
            [existing removeFromSuperview];
            objc_setAssociatedObject(self, kLGVolumeHUDGlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
        LGVolumeHUDVibranceView *existingVib = objc_getAssociatedObject(self, kLGVolumeHUDVibranceKey);
        if (existingVib) {
            [existingVib removeFromSuperview];
            objc_setAssociatedObject(self, kLGVolumeHUDVibranceKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
        LGVolumeHUDRestoreHidden(base);
        LGVolumeHUDRestoreHidden(cap);
        LGVolumeHUDRestoreHidden(shadow);
        LGVolumeHUDRestoreLayer(self);
        LGVolumeHUDRestoreLayer(sliderWrapper);
        LGVolumeHUDRestoreLayer(sliderView);
        if (sliderView && LGVolumeHUDNeedsLegacyMaterialWorkaround()) {
            for (UIView *subview in sliderView.subviews) {
                if ([subview isKindOfClass:NSClassFromString(@"MTMaterialView")]) {
                    LGVolumeHUDRestoreLayer(subview);
                }
            }
        }
        LGSetVolumeHUDBackgroundMaterialsHidden(self, NO);
        return;
    }

    if (!self.window || CGRectIsEmpty(self.bounds)) return;

    LGVolumeHUDSaveAndHide(base);
    LGVolumeHUDSaveAndHide(cap);
    LGVolumeHUDSaveAndHide(shadow);
    LGSetVolumeHUDBackgroundMaterialsHidden(self, YES);

    LGVolumeHUDVibranceView *vibrance = objc_getAssociatedObject(self, kLGVolumeHUDVibranceKey);
    if (!vibrance) {
        vibrance = [[LGVolumeHUDVibranceView alloc] initWithFrame:self.bounds];
        if (vibrance) {
            objc_setAssociatedObject(self, kLGVolumeHUDVibranceKey, vibrance, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    if (vibrance) {
        if (sliderWrapper) {
            if (vibrance.superview != self ||
                ([self.subviews indexOfObjectIdenticalTo:vibrance] > [self.subviews indexOfObjectIdenticalTo:sliderWrapper])) {
                [self insertSubview:vibrance belowSubview:sliderWrapper];
            }
        } else if (vibrance.superview != self) {
            [self addSubview:vibrance];
        }
    }

    LGLiveBackdropView *glass = objc_getAssociatedObject(self, kLGVolumeHUDGlassKey);
    BOOL freshInject = NO;
    if (!glass) {
        glass = LGCreateRegisteredGlass(self.bounds, nil, @"VolumeHUD");
        if (!glass) return;
        objc_setAssociatedObject(self, kLGVolumeHUDGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        lgTrackGlass(glass, @"VolumeHUD", nil);
        [self insertSubview:glass atIndex:0];
        freshInject = YES;
    } else if (glass.superview != self || self.subviews.firstObject != glass) {
        [self insertSubview:glass atIndex:0];
    }

    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5f;

    glass.hidden = NO;
    if (!CGRectEqualToRect(glass.frame, self.bounds)) glass.frame = self.bounds;
    glass.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        glass.layer.cornerCurve = kCACornerCurveContinuous;
    }
    glass.layer.masksToBounds = YES;
    if (freshInject) [glass applyFilters];

    if (vibrance) {
        vibrance.hidden = NO;
        if (!CGRectEqualToRect(vibrance.frame, self.bounds)) vibrance.frame = self.bounds;
        vibrance.layer.cornerRadius = radius;
        if (@available(iOS 13.0, *)) {
            vibrance.layer.cornerCurve = kCACornerCurveContinuous;
        }
        vibrance.layer.masksToBounds = YES;
        [vibrance applyVibranceFilters];
    }

    LGVolumeHUDSaveLayer(self);
    self.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }

    if (sliderWrapper) {
        LGVolumeHUDSaveLayer(sliderWrapper);
        sliderWrapper.layer.cornerRadius = radius;
        if (@available(iOS 13.0, *)) {
            sliderWrapper.layer.cornerCurve = kCACornerCurveContinuous;
        }
        sliderWrapper.layer.masksToBounds = YES;
    }

    if (sliderView) {
        LGVolumeHUDSaveLayer(sliderView);
        sliderView.layer.cornerRadius = radius;
        if (@available(iOS 13.0, *)) {
            sliderView.layer.cornerCurve = kCACornerCurveContinuous;
        }
        sliderView.layer.masksToBounds = YES;
        if (LGVolumeHUDNeedsLegacyMaterialWorkaround()) {
            for (UIView *subview in sliderView.subviews) {
                if (![subview isKindOfClass:NSClassFromString(@"MTMaterialView")]) continue;
                LGVolumeHUDSaveLayer(subview);
                subview.layer.cornerRadius = radius;
                subview.layer.cornerCurve = kCACornerCurveContinuous;
                subview.layer.masksToBounds = YES;
            }
        }
    }
    LGScheduleVolumeHUDProbe(self);
}

%group LGVolumeHUDHooks

%hook SBElasticSliderMaterialWrapperView

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        LGUpdateVolumeHUDGlass(self);
    }
    return self;
}

- (instancetype)initWithSliderView:(id)sliderView {
    self = %orig;
    if (self) {
        LGUpdateVolumeHUDGlass(self);
    }
    return self;
}

- (void)didMoveToWindow {
    %orig;
    LGUpdateVolumeHUDGlass(self);
}

- (void)layoutSubviews {
    %orig;
    LGUpdateVolumeHUDGlass(self);
}

- (void)_setContinuousCornerRadius:(double)radius {
    if (LGVolumeHUDEnabled()) {
        CGFloat pillRadius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5f;
        %orig((double)pillRadius);
        LGLiveBackdropView *glass = objc_getAssociatedObject(self, kLGVolumeHUDGlassKey);
        if (glass) {
            glass.layer.cornerRadius = pillRadius;
            if (@available(iOS 13.0, *)) {
                glass.layer.cornerCurve = kCACornerCurveContinuous;
            }
        }
        LGVolumeHUDVibranceView *vibrance = objc_getAssociatedObject(self, kLGVolumeHUDVibranceKey);
        if (vibrance) {
            vibrance.layer.cornerRadius = pillRadius;
            if (@available(iOS 13.0, *)) {
                vibrance.layer.cornerCurve = kCACornerCurveContinuous;
            }
        }
    } else {
        %orig;
    }
}

%end

%end

%ctor {
    if (!LGIsSpringBoardProcess()) return;
    %init(LGVolumeHUDHooks);
    lgObservePreferenceReload(^{
        LGLog(@"VolumeHUD: Preferences reloaded");
        for (SBElasticSliderMaterialWrapperView *wrapper in sLGVolumeHUDWrappers.allObjects) {
            LGUpdateVolumeHUDGlass(wrapper);
        }
    });
}
