#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"

#import "../Shared/LGFramework.h"

static BOOL LGAssistiveTouchEnabled(void) {
    return lgHostEnabled(@"AssistiveTouch");
}

static UIImage *CreateExposureGlowImage(CGFloat diameter) {
    if (diameter <= 0.5 || !isfinite(diameter)) return nil;
    CGSize size = CGSizeMake(diameter, diameter);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) {
        UIGraphicsEndImageContext();
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.95].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.65].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.25].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.00].CGColor
    ];
    CGFloat locations[] = {0.0, 0.28, 0.65, 1.0};
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)colors, locations);

    CGPoint center = CGPointMake(diameter / 2.0, diameter / 2.0);
    CGContextDrawRadialGradient(ctx, gradient, center, 0.0, center, diameter / 2.0, kCGGradientDrawsAfterEndLocation);

    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@interface ASSHeldGlassView : UIView
@property (nonatomic, strong) UIView *backgroundContainer;
@property (nonatomic, strong) LGAdjustableBlurView *blurView;
@property (nonatomic, strong) LGLiveBackdropView *lgView;
@property (nonatomic, strong) UIView *darkTintView;
@property (nonatomic, strong) UIImageView *exposureGlowView;
- (void)updateShapeForBounds:(CGRect)bounds;
- (void)updateShapeWithScale:(CGFloat)baseScale stretchX:(CGFloat)stretchX stretchY:(CGFloat)stretchY shiftX:(CGFloat)shiftX shiftY:(CGFloat)shiftY;
@end

@implementation ASSHeldGlassView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.clipsToBounds = NO;
        self.alpha = 0.0;

        CGFloat radius = MIN(frame.size.width, frame.size.height) / 2.0;

        self.backgroundContainer = [[UIView alloc] initWithFrame:self.bounds];
        self.backgroundContainer.center = CGPointMake(frame.size.width / 2.0, frame.size.height / 2.0);
        self.backgroundContainer.clipsToBounds = YES;
        self.backgroundContainer.layer.cornerRadius = radius;
        self.backgroundContainer.layer.cornerCurve = kCACornerCurveContinuous;
        self.backgroundContainer.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.20];
        [self addSubview:self.backgroundContainer];

        self.blurView = [[LGAdjustableBlurView alloc] initWithFrame:self.backgroundContainer.bounds blurRadius:1.0];
        self.blurView.qualityScale = 0.75;
        self.blurView.clipsToBounds = YES;
        self.blurView.layer.cornerRadius = radius;
        self.blurView.layer.cornerCurve = kCACornerCurveContinuous;
        [self.backgroundContainer addSubview:self.blurView];

        self.lgView = [[LGLiveBackdropView alloc] initWithFrame:self.backgroundContainer.bounds
                                                     groupName:nil
                                                    filterType:@"dylv.liquidglass.assistivetouch"];
        self.lgView.clipsToBounds = YES;
        self.lgView.layer.cornerRadius = radius;
        self.lgView.layer.cornerCurve = kCACornerCurveContinuous;
        [self.backgroundContainer addSubview:self.lgView];

        self.darkTintView = [[UIView alloc] initWithFrame:self.backgroundContainer.bounds];
        self.darkTintView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
        self.darkTintView.clipsToBounds = YES;
        self.darkTintView.layer.cornerRadius = radius;
        self.darkTintView.layer.cornerCurve = kCACornerCurveContinuous;
        [self.backgroundContainer addSubview:self.darkTintView];

        CGFloat glowSize = MAX(frame.size.width, frame.size.height) * 1.55;
        self.exposureGlowView = [[UIImageView alloc] initWithImage:CreateExposureGlowImage(glowSize)];
        self.exposureGlowView.frame = CGRectMake(0, 0, glowSize, glowSize);
        self.exposureGlowView.center = CGPointMake(self.backgroundContainer.bounds.size.width / 2.0, self.backgroundContainer.bounds.size.height / 2.0);
        self.exposureGlowView.alpha = 0.0;
        [self.backgroundContainer addSubview:self.exposureGlowView];

        if (!self.lgView.lgFilterAttached) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                ASSHeldGlassView *strongSelf = weakSelf;
                if (strongSelf && strongSelf.window && !strongSelf.lgView.lgFilterAttached) {
                    [strongSelf.lgView applyFilters];
                    [strongSelf.lgView lgInvalidateFilterContents];
                }
            });
        }
    }
    return self;
}

- (void)updateShapeForBounds:(CGRect)bounds {
    self.frame = bounds;
    if (bounds.size.width > 0.5 && bounds.size.height > 0.5 && !self.exposureGlowView.image) {
        CGFloat glowSize = MAX(bounds.size.width, bounds.size.height) * 1.55;
        self.exposureGlowView.image = CreateExposureGlowImage(glowSize);
        self.exposureGlowView.bounds = CGRectMake(0, 0, glowSize, glowSize);
    }
    [self updateShapeWithScale:1.0 stretchX:1.0 stretchY:1.0 shiftX:0 shiftY:0];
}

- (void)updateShapeWithScale:(CGFloat)baseScale stretchX:(CGFloat)stretchX stretchY:(CGFloat)stretchY shiftX:(CGFloat)shiftX shiftY:(CGFloat)shiftY {
    CGFloat newW = self.bounds.size.width * baseScale * stretchX;
    CGFloat newH = self.bounds.size.height * baseScale * stretchY;
    CGFloat newRadius = MIN(newW, newH) / 2.0;

    CGRect newBounds = CGRectMake(0, 0, newW, newH);
    CGPoint center = CGPointMake(self.bounds.size.width / 2.0 + shiftX, self.bounds.size.height / 2.0 + shiftY);

    self.backgroundContainer.bounds = newBounds;
    self.backgroundContainer.center = center;
    self.backgroundContainer.layer.cornerRadius = newRadius;

    self.blurView.frame = newBounds;
    self.blurView.layer.cornerRadius = newRadius;

    self.lgView.frame = newBounds;
    self.lgView.layer.cornerRadius = newRadius;

    self.darkTintView.frame = newBounds;
    self.darkTintView.layer.cornerRadius = newRadius;

    self.exposureGlowView.center = CGPointMake(newW / 2.0, newH / 2.0);
}

@end

@interface ASSVibranceOverlayView : UIView
@property (nonatomic, assign) CGSize baseSize;
- (void)updateShapeForBounds:(CGRect)bounds;
- (void)updateShapeWithScale:(CGFloat)baseScale stretchX:(CGFloat)stretchX stretchY:(CGFloat)stretchY shiftX:(CGFloat)shiftX shiftY:(CGFloat)shiftY;
- (void)forceReapplyForRegistrationRace;
@end

@implementation ASSVibranceOverlayView

+ (Class)layerClass {
    return NSClassFromString(@"CABackdropLayer") ?: [CALayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.clipsToBounds = YES;
        self.alpha = 0.0;
        _baseSize = frame.size;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        [self applyFilters];
    }
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self applyFilters];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyFilters];
}

- (void)applyFilters {
    CALayer *layer = self.layer;
    Class backdropCls = NSClassFromString(@"CABackdropLayer");
    if (!backdropCls || ![layer isKindOfClass:backdropCls]) return;

    @try {
        [layer setValue:@NO forKey:@"layerUsesCoreImageFilters"];
        [layer setValue:@YES forKey:@"windowServerAware"];
        [layer setValue:@(0.5) forKey:@"scale"];
        if (layer.filters.count > 0) return;

        Class filterCls = NSClassFromString(@"CAFilter");
        if (!filterCls) return;

        NSMutableArray *filters = [NSMutableArray array];

        id satFilter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
            filterCls, NSSelectorFromString(@"filterWithType:"), @"colorSaturate");
        if (satFilter) {
            @try { [satFilter setValue:@(5.00) forKey:@"inputAmount"]; } @catch (...) {}
            [filters addObject:satFilter];
        }

        id contrastFilter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
            filterCls, NSSelectorFromString(@"filterWithType:"), @"colorContrast");
        if (contrastFilter) {
            @try { [contrastFilter setValue:@(1.22) forKey:@"inputAmount"]; } @catch (...) {}
            [filters addObject:contrastFilter];
        }

        layer.filters = filters;
    } @catch (NSException *e) {}
}

- (void)forceReapplyForRegistrationRace {
    [self applyFilters];
}

- (void)updateShapeForBounds:(CGRect)bounds {
    self.baseSize = bounds.size;
    self.frame = bounds;
    [self updateShapeWithScale:1.0 stretchX:1.0 stretchY:1.0 shiftX:0 shiftY:0];
}

- (void)updateShapeWithScale:(CGFloat)baseScale stretchX:(CGFloat)stretchX stretchY:(CGFloat)stretchY shiftX:(CGFloat)shiftX shiftY:(CGFloat)shiftY {
    UIView *superv = self.superview;
    CGFloat superW = superv ? superv.bounds.size.width : self.baseSize.width;
    CGFloat superH = superv ? superv.bounds.size.height : self.baseSize.height;
    CGFloat baseW = (superW > 0) ? superW : 60.0;
    CGFloat baseH = (superH > 0) ? superH : 60.0;
    CGFloat newW = baseW * baseScale * stretchX;
    CGFloat newH = baseH * baseScale * stretchY;
    CGFloat newRadius = MIN(newW, newH) / 2.0;

    CGRect newBounds = CGRectMake(0, 0, newW, newH);
    CGPoint center = CGPointMake(baseW / 2.0 + shiftX, baseH / 2.0 + shiftY);

    self.bounds = newBounds;
    self.center = center;
    self.layer.cornerRadius = newRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
}

@end

static UIImage *CreateRadialGlowImage(CGFloat diameter) {
    if (diameter <= 0.5 || !isfinite(diameter)) return nil;
    CGSize size = CGSizeMake(diameter, diameter);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) {
        UIGraphicsEndImageContext();
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.40].CGColor,
                        (id)[UIColor colorWithWhite:1.0 alpha:0.16].CGColor,
                        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    CGFloat locations[] = {0.0, 0.45, 1.0};
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)colors, locations);

    CGPoint center = CGPointMake(diameter / 2.0, diameter / 2.0);
    CGContextDrawRadialGradient(ctx, gradient, center, 0.0, center, diameter / 2.0, kCGGradientDrawsAfterEndLocation);

    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@interface ASSMenuInnerGlowView : UIView
@property (nonatomic, strong) UIImageView *glowImageView;
@property (nonatomic, assign) BOOL isTrackingTouch;
- (void)handleTouchDownAtPoint:(CGPoint)pt;
- (void)handleTouchMovedToPoint:(CGPoint)pt;
- (void)handleTouchEnded;
- (void)resetGlowImmediately;
- (void)updateLayoutWithBounds:(CGRect)bounds;
@end

@implementation ASSMenuInnerGlowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = YES;
        self.layer.cornerRadius = 28.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;

        CGFloat diameter = 360.0;
        self.glowImageView = [[UIImageView alloc] initWithImage:CreateRadialGlowImage(diameter)];
        self.glowImageView.frame = CGRectMake(0, 0, diameter, diameter);
        self.glowImageView.center = CGPointMake(frame.size.width / 2.0, frame.size.height / 2.0);
        self.glowImageView.alpha = 0.0;
        [self addSubview:self.glowImageView];
    }
    return self;
}

- (void)updateLayoutWithBounds:(CGRect)bounds {
    self.frame = bounds;
    self.layer.cornerRadius = 28.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
}

- (void)handleTouchDownAtPoint:(CGPoint)pt {
    self.isTrackingTouch = YES;
    self.glowImageView.center = pt;
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
        self.glowImageView.alpha = 0.55;
    } completion:nil];
}

- (void)handleTouchMovedToPoint:(CGPoint)pt {
    self.glowImageView.center = pt;
    if (!self.isTrackingTouch || self.glowImageView.alpha < 0.50) {
        self.isTrackingTouch = YES;
        [UIView animateWithDuration:0.10 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
            self.glowImageView.alpha = 0.55;
        } completion:nil];
    }
}

- (void)handleTouchEnded {
    self.isTrackingTouch = NO;
    [UIView animateWithDuration:0.65 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
        self.glowImageView.alpha = 0.0;
    } completion:nil];
}

- (void)resetGlowImmediately {
    self.isTrackingTouch = NO;
    [self.glowImageView.layer removeAllAnimations];
    self.glowImageView.alpha = 0.0;
}

@end

@interface HNDRocker : UIView
@property (nonatomic, assign) BOOL isFullMenuVisible;
- (void)ass_handleTouchDownAtPoint:(CGPoint)pt;
- (void)ass_handleTouchMovedToPoint:(CGPoint)pt;
- (void)ass_handleTouchEnded;
- (void)ass_enforceCircularShape;
- (ASSHeldGlassView *)ass_glassView;
- (ASSVibranceOverlayView *)ass_vibranceView;
- (ASSMenuInnerGlowView *)ass_menuGlowView;
- (UIImageView *)ass_nubbitForeground;
- (UIVisualEffectView *)ass_backdropView;
- (void)ass_playMenuBounceAnimation;
- (void)ass_triggerMotionBlurForDuration:(CGFloat)duration peakRadius:(CGFloat)peak;
@end

static float sTransitionSpeedMultiplier = 1.0f;

%group LGAssistiveTouchHooks

%hook CALayer

- (void)addAnimation:(CAAnimation *)anim forKey:(NSString *)key {
    if (sTransitionSpeedMultiplier > 1.01f && anim) {
        float currentSpeed = anim.speed;
        anim.speed = (currentSpeed > 0.0f) ? (currentSpeed * sTransitionSpeedMultiplier) : sTransitionSpeedMultiplier;
    }
    %orig(anim, key);
}

%end

%hook CATransaction

+ (void)setAnimationDuration:(NSTimeInterval)dur {
    if (sTransitionSpeedMultiplier > 1.01f && dur > 0.0) {
        dur = dur / (NSTimeInterval)sTransitionSpeedMultiplier;
    }
    %orig(dur);
}

%end


static const void *kAssGlassViewKey = &kAssGlassViewKey;
static const void *kAssVibranceViewKey = &kAssVibranceViewKey;
static const void *kAssMenuGlowViewKey = &kAssMenuGlowViewKey;
static const void *kAssIsHeldKey = &kAssIsHeldKey;
static const void *kAssStartPointKey = &kAssStartPointKey;
static const void *kAssBackdropAlphaKey = &kAssBackdropAlphaKey;
static const void *kAssMotionBlurGenKey = &kAssMotionBlurGenKey;
static __weak HNDRocker *sCurrentActiveRocker = nil;

static void LGAssistiveTouchTeardownRocker(HNDRocker *rocker) {
    if (!rocker) return;
    objc_setAssociatedObject(rocker, kAssIsHeldKey, @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ASSHeldGlassView *glass = [rocker ass_glassView];
    if (glass) {
        [glass.layer removeAllAnimations];
        glass.alpha = 0.0;
        glass.hidden = YES;
        glass.exposureGlowView.alpha = 0.0;
    }
    ASSVibranceOverlayView *vibe = [rocker ass_vibranceView];
    if (vibe) {
        [vibe.layer removeAllAnimations];
        vibe.alpha = 0.0;
        vibe.hidden = YES;
    }
    ASSMenuInnerGlowView *menuGlow = [rocker ass_menuGlowView];
    if (menuGlow) {
        [menuGlow resetGlowImmediately];
    }
    UIVisualEffectView *backdrop = [rocker ass_backdropView];
    NSNumber *savedAlpha = objc_getAssociatedObject(rocker, kAssBackdropAlphaKey);
    if (backdrop && savedAlpha) {
        backdrop.alpha = savedAlpha.doubleValue;
    }
    objc_setAssociatedObject(rocker, kAssBackdropAlphaKey, nil, OBJC_ASSOCIATION_ASSIGN);
    UIImageView *fg = [rocker ass_nubbitForeground];
    if (fg) {
        [fg.layer removeAllAnimations];
        fg.transform = CGAffineTransformIdentity;
        fg.layer.shadowOpacity = 0.0;
        fg.layer.filters = nil;
    }
    [rocker.layer removeAnimationForKey:@"ass_motionBlurAnim"];
    NSMutableArray *filters = [rocker.layer.filters mutableCopy];
    if (filters.count) {
        NSMutableArray *kept = [NSMutableArray arrayWithCapacity:filters.count];
        for (id f in filters) {
            NSString *name = [f respondsToSelector:@selector(name)]
                ? ((NSString *(*)(id, SEL))objc_msgSend)(f, @selector(name)) : nil;
            if (![name isEqualToString:@"ass_motionBlur"]) [kept addObject:f];
        }
        rocker.layer.filters = kept.count ? kept : nil;
    }
}

%hook HNDRocker

- (BOOL)_usesCircularNubbit {
    if (!LGAssistiveTouchEnabled()) return %orig;
    return YES;
}

%new
- (void)ass_playMenuBounceAnimation {
    if (![self isFullMenuVisible]) return;
    CALayer *targetLayer = self.layer;
    if (!targetLayer) return;

    if ([targetLayer animationForKey:@"ass_menuBounce"]) {
        return;
    }

    CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    anim.duration = 0.62;
    anim.values = @[
        @(1.0),
        @(1.036),
        @(0.990),
        @(1.004),
        @(1.0)
    ];
    anim.keyTimes = @[
        @(0.0),
        @(0.30),
        @(0.62),
        @(0.82),
        @(1.0)
    ];
    anim.timingFunctions = @[
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]
    ];
    anim.removedOnCompletion = YES;
    [targetLayer addAnimation:anim forKey:@"ass_menuBounce"];
}

%new
- (void)ass_triggerMotionBlurForDuration:(CGFloat)duration peakRadius:(CGFloat)peak {
    if (!LGAssistiveTouchEnabled()) return;
    Class filterCls = NSClassFromString(@"CAFilter");
    if (!filterCls) return;

    CALayer *layer = self.layer;
    if (!layer) return;

    NSMutableArray *filters = [layer.filters mutableCopy] ?: [NSMutableArray array];
    id blurFilter = nil;
    for (id f in filters) {
        NSString *name = nil;
        if ([f respondsToSelector:@selector(name)]) {
            name = ((NSString *(*)(id, SEL))objc_msgSend)(f, @selector(name));
        }
        if ([name isEqualToString:@"ass_motionBlur"]) {
            blurFilter = f;
            break;
        }
    }

    if (!blurFilter) {
        blurFilter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
            filterCls, NSSelectorFromString(@"filterWithType:"), @"gaussianBlur");
        if (blurFilter) {
            @try {
                [blurFilter setValue:@"ass_motionBlur" forKey:@"name"];
                [blurFilter setValue:@(0.0) forKey:@"inputRadius"];
            } @catch (...) {}
            [filters addObject:blurFilter];
            layer.filters = filters;
        }
    }

    if (blurFilter) {
        NSUInteger gen = [objc_getAssociatedObject(self, kAssMotionBlurGenKey) unsignedIntegerValue] + 1;
        objc_setAssociatedObject(self, kAssMotionBlurGenKey, @(gen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        [layer removeAnimationForKey:@"ass_motionBlurAnim"];

        CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"filters.ass_motionBlur.inputRadius"];
        anim.duration = duration;
        anim.values = @[
            @(0.0),
            @(peak),
            @(peak * 0.35),
            @(0.0)
        ];
        anim.keyTimes = @[
            @(0.0),
            @(0.25),
            @(0.60),
            @(1.0)
        ];
        anim.timingFunctions = @[
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn],
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]
        ];
        anim.removedOnCompletion = YES;
        __weak HNDRocker *weakSelf = self;
        if (backdrop && !objc_getAssociatedObject(self, kAssBackdropAlphaKey)) {
        objc_setAssociatedObject(self, kAssBackdropAlphaKey, @(backdrop.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [CATransaction begin];
        [CATransaction setCompletionBlock:^{
            HNDRocker *strongSelf = weakSelf;
            if (!strongSelf) return;
            if ([objc_getAssociatedObject(strongSelf, kAssMotionBlurGenKey) unsignedIntegerValue] != gen) return;
            NSMutableArray *curFilters = [strongSelf.layer.filters mutableCopy];
            if (!curFilters.count) return;
            NSMutableArray *kept = [NSMutableArray arrayWithCapacity:curFilters.count];
            for (id f in curFilters) {
                NSString *name = [f respondsToSelector:@selector(name)]
                    ? ((NSString *(*)(id, SEL))objc_msgSend)(f, @selector(name)) : nil;
                if (![name isEqualToString:@"ass_motionBlur"]) [kept addObject:f];
            }
            strongSelf.layer.filters = kept.count ? kept : nil;
        }];
        [layer addAnimation:anim forKey:@"ass_motionBlurAnim"];
        [CATransaction commit];
    }
}

- (void)_loadInitialMenuItems {
    %orig;
    if (LGAssistiveTouchEnabled()) [self ass_playMenuBounceAnimation];
}

- (void)_loadMoreMenuItems {
    %orig;
    if (LGAssistiveTouchEnabled()) [self ass_playMenuBounceAnimation];
}

- (void)_loadGesturesMenuItems {
    %orig;
    if (LGAssistiveTouchEnabled()) [self ass_playMenuBounceAnimation];
}

- (void)_loadRotateMenuItems {
    %orig;
    if (LGAssistiveTouchEnabled()) [self ass_playMenuBounceAnimation];
}

- (void)_loadScrollMenuItems {
    %orig;
    if (LGAssistiveTouchEnabled()) [self ass_playMenuBounceAnimation];
}

- (void)_loadHardwareMenuItems {
    %orig;
    if (LGAssistiveTouchEnabled()) [self ass_playMenuBounceAnimation];
}

- (void)_loadFavoritesMenuItems {
    %orig;
    if (LGAssistiveTouchEnabled()) [self ass_playMenuBounceAnimation];
}

- (void)_loadDwellMenuItems {
    %orig;
    if (LGAssistiveTouchEnabled()) [self ass_playMenuBounceAnimation];
}

- (void)_loadSecureIntentMenuItems {
    %orig;
    if (LGAssistiveTouchEnabled()) [self ass_playMenuBounceAnimation];
}

- (void)performPress:(int)button type:(int)type source:(int)source {
    %orig(button, type, source);
    if (LGAssistiveTouchEnabled()) [self ass_playMenuBounceAnimation];
}

- (void)setFullMenuVisible:(BOOL)visible atPoint:(CGPoint)point {
    if (!LGAssistiveTouchEnabled()) { %orig(visible, point); return; }
    float prev = sTransitionSpeedMultiplier;
    sTransitionSpeedMultiplier = visible ? 2.0f : 1.25f;
    @try {
        %orig(visible, point);
    } @finally {
        sTransitionSpeedMultiplier = prev;
    }
    if (visible) {
        [self ass_triggerMotionBlurForDuration:0.15 peakRadius:4.5];
    } else {
        [self ass_triggerMotionBlurForDuration:0.18 peakRadius:3.6];
        [[self ass_menuGlowView] resetGlowImmediately];
        UIVisualEffectView *backdrop = [self ass_backdropView];
        if (backdrop) {
            [backdrop.layer removeAllAnimations];
            backdrop.transform = CGAffineTransformIdentity;
        }
    }
}

- (void)_menuExited {
    if (!LGAssistiveTouchEnabled()) { %orig; return; }
    float prev = sTransitionSpeedMultiplier;
    sTransitionSpeedMultiplier = 1.25f;
    [self ass_triggerMotionBlurForDuration:0.18 peakRadius:3.6];
    [[self ass_menuGlowView] resetGlowImmediately];
    UIVisualEffectView *backdrop = [self ass_backdropView];
    if (backdrop) {
        [backdrop.layer removeAllAnimations];
        backdrop.transform = CGAffineTransformIdentity;
    }
    @try {
        %orig;
    } @finally {
        sTransitionSpeedMultiplier = prev;
    }
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        sCurrentActiveRocker = self;
        if (!LGAssistiveTouchEnabled()) {
            LGAssistiveTouchTeardownRocker(self);
            return;
        }

        ASSHeldGlassView *glass = [self ass_glassView];
        if (!glass) {
            glass = [[ASSHeldGlassView alloc] initWithFrame:self.bounds];
            objc_setAssociatedObject(self, kAssGlassViewKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self insertSubview:glass atIndex:1];
        }
        [glass updateShapeForBounds:self.bounds];
        glass.alpha = 0.0;
        glass.hidden = YES;

        ASSVibranceOverlayView *vibe = [self ass_vibranceView];
        if (!vibe) {
            vibe = [[ASSVibranceOverlayView alloc] initWithFrame:self.bounds];
            objc_setAssociatedObject(self, kAssVibranceViewKey, vibe, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self addSubview:vibe];
        }
        [vibe updateShapeForBounds:self.bounds];
        [self bringSubviewToFront:vibe];
        vibe.alpha = 0.0;
        vibe.hidden = YES;

        [self ass_enforceCircularShape];
    }
}

- (void)layoutSubviews {
    %orig;
    if (!LGAssistiveTouchEnabled()) {
        LGAssistiveTouchTeardownRocker(self);
        return;
    }
    if ([self isFullMenuVisible]) {
        UIVisualEffectView *backdrop = [self ass_backdropView];
        if (backdrop) {
            ASSMenuInnerGlowView *menuGlow = [self ass_menuGlowView];
            if (!menuGlow) {
                menuGlow = [[ASSMenuInnerGlowView alloc] initWithFrame:backdrop.bounds];
                objc_setAssociatedObject(self, kAssMenuGlowViewKey, menuGlow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [backdrop.contentView insertSubview:menuGlow atIndex:0];
            }
            [menuGlow updateLayoutWithBounds:backdrop.bounds];
        }
    } else {
        [self ass_enforceCircularShape];
    }
    ASSVibranceOverlayView *vibe = [self ass_vibranceView];
    if (vibe) {
        if (![self isFullMenuVisible] && ![objc_getAssociatedObject(self, kAssIsHeldKey) boolValue]) {
            [vibe updateShapeForBounds:self.bounds];
            vibe.alpha = 0.0;
            vibe.hidden = YES;
        }
        [self bringSubviewToFront:vibe];
    }
}

- (void)setFrame:(CGRect)frame {
    %orig(frame);
    if (!LGAssistiveTouchEnabled() || [objc_getAssociatedObject(self, kAssIsHeldKey) boolValue]) return;
    ASSHeldGlassView *glass = [self ass_glassView];
    if (glass) {
        [glass updateShapeForBounds:self.bounds];
    }
    ASSVibranceOverlayView *vibe = [self ass_vibranceView];
    if (vibe) {
        [vibe updateShapeForBounds:self.bounds];
        [self bringSubviewToFront:vibe];
    }
    [self ass_enforceCircularShape];
}

- (void)setBounds:(CGRect)bounds {
    %orig(bounds);
    if (!LGAssistiveTouchEnabled() || [objc_getAssociatedObject(self, kAssIsHeldKey) boolValue]) return;
    ASSHeldGlassView *glass = [self ass_glassView];
    if (glass) {
        [glass updateShapeForBounds:self.bounds];
    }
    ASSVibranceOverlayView *vibe = [self ass_vibranceView];
    if (vibe) {
        [vibe updateShapeForBounds:self.bounds];
        [self bringSubviewToFront:vibe];
    }
    [self ass_enforceCircularShape];
}

- (void)fadeNubbit {
    %orig;
    if (!LGAssistiveTouchEnabled()) return;
    NSNumber *held = objc_getAssociatedObject(self, kAssIsHeldKey);
    if (![held boolValue]) {
        ASSHeldGlassView *glass = [self ass_glassView];
        if (glass) glass.alpha = 0.0;
        ASSVibranceOverlayView *vibe = [self ass_vibranceView];
        if (vibe) vibe.alpha = 0.0;
    }
    [self ass_enforceCircularShape];
}

- (void)_updateNubbitFadedProperties {
    %orig;
    if (!LGAssistiveTouchEnabled()) return;
    NSNumber *held = objc_getAssociatedObject(self, kAssIsHeldKey);
    if (![held boolValue]) {
        ASSHeldGlassView *glass = [self ass_glassView];
        if (glass) glass.alpha = 0.0;
        ASSVibranceOverlayView *vibe = [self ass_vibranceView];
        if (vibe) vibe.alpha = 0.0;
    }
    [self ass_enforceCircularShape];
}

- (void)handleRealDownEvent:(CGPoint)point {
    %orig(point);
    if (!LGAssistiveTouchEnabled()) return;
    if ([self isFullMenuVisible]) {
        UIVisualEffectView *backdrop = [self ass_backdropView];
        CGPoint localPt = backdrop ? [self convertPoint:point toView:backdrop.contentView] : point;
        [[self ass_menuGlowView] handleTouchDownAtPoint:localPt];
    } else {
        [self ass_handleTouchDownAtPoint:point];
    }
}

- (void)handleRealMoveEvent:(CGPoint)point maxOrb:(double)maxOrb currentForce:(double)currentForce {
    %orig(point, maxOrb, currentForce);
    if (!LGAssistiveTouchEnabled()) return;
    if ([self isFullMenuVisible]) {
        UIVisualEffectView *backdrop = [self ass_backdropView];
        CGPoint localPt = backdrop ? [self convertPoint:point toView:backdrop.contentView] : point;
        [[self ass_menuGlowView] handleTouchMovedToPoint:localPt];
    } else {
        [self ass_handleTouchMovedToPoint:point];
    }
}

- (void)handleRealUpEvent:(CGPoint)point maxOrb:(double)maxOrb {
    %orig(point, maxOrb);
    if (!LGAssistiveTouchEnabled()) return;
    if ([self isFullMenuVisible]) {
        [self ass_playMenuBounceAnimation];
        [[self ass_menuGlowView] handleTouchEnded];
    } else {
        [self ass_handleTouchEnded];
    }
}

- (void)_updateSelectedButtonWithPoint:(CGPoint)point {
    %orig(point);
    if (!LGAssistiveTouchEnabled()) return;
    if ([self isFullMenuVisible]) {
        UIVisualEffectView *backdrop = [self ass_backdropView];
        CGPoint localPt = backdrop ? [self convertPoint:point toView:backdrop.contentView] : point;
        [[self ass_menuGlowView] handleTouchMovedToPoint:localPt];
    }
}

- (void)showNubbitPressedState:(BOOL)pressed {
    %orig(pressed);
    if (!LGAssistiveTouchEnabled()) return;
    if (![self isFullMenuVisible]) {
        if (pressed) {
            [self ass_handleTouchDownAtPoint:CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0)];
        } else {
            [self ass_handleTouchEnded];
        }
    }
}

- (void)transitionNubbitToMenu:(CGPoint)point concurrentAnimation:(id)block1 animationCompleted:(id)block2 {
    if (!LGAssistiveTouchEnabled()) { %orig(point, block1, block2); return; }
    float prev = sTransitionSpeedMultiplier;
    sTransitionSpeedMultiplier = 2.0f;
    objc_setAssociatedObject(self, kAssIsHeldKey, @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    ASSHeldGlassView *glass = [self ass_glassView];
    if (glass) {
        [glass.layer removeAllAnimations];
        glass.alpha = 0.0;
        glass.hidden = YES;
        glass.exposureGlowView.alpha = 0.0;
    }

    ASSVibranceOverlayView *vibe = [self ass_vibranceView];
    if (vibe) {
        [vibe.layer removeAllAnimations];
        vibe.alpha = 0.0;
        vibe.hidden = YES;
    }

    @try {
        %orig(point, block1, block2);
    } @finally {
        sTransitionSpeedMultiplier = prev;
    }
    [self ass_triggerMotionBlurForDuration:0.15 peakRadius:4.5];

    UIVisualEffectView *backdrop = [self ass_backdropView];
    if (backdrop) {
        backdrop.alpha = 1.0;
        backdrop.layer.cornerRadius = 28.0;
        backdrop.layer.cornerCurve = kCACornerCurveContinuous;
        backdrop.layer.masksToBounds = YES;

        ASSMenuInnerGlowView *menuGlow = [self ass_menuGlowView];
        if (!menuGlow) {
            menuGlow = [[ASSMenuInnerGlowView alloc] initWithFrame:backdrop.bounds];
            objc_setAssociatedObject(self, kAssMenuGlowViewKey, menuGlow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [backdrop.contentView insertSubview:menuGlow atIndex:0];
        }
        [menuGlow resetGlowImmediately];
        [menuGlow updateLayoutWithBounds:backdrop.bounds];
    }
}

- (void)transitionMenuToNubbit:(CGPoint)point changeAlpha:(BOOL)changeAlpha animate:(BOOL)animate {
    if (!LGAssistiveTouchEnabled()) { %orig(point, changeAlpha, animate); return; }
    float prev = sTransitionSpeedMultiplier;
    sTransitionSpeedMultiplier = 1.25f;
    objc_setAssociatedObject(self, kAssIsHeldKey, @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self ass_triggerMotionBlurForDuration:0.18 peakRadius:3.6];
    [[self ass_menuGlowView] resetGlowImmediately];

    ASSHeldGlassView *glass = [self ass_glassView];
    if (glass) {
        [glass.layer removeAllAnimations];
        glass.alpha = 0.0;
        glass.hidden = YES;
        glass.exposureGlowView.alpha = 0.0;
    }

    ASSVibranceOverlayView *vibe = [self ass_vibranceView];
    if (vibe) {
        [vibe.layer removeAllAnimations];
        vibe.alpha = 0.0;
        vibe.hidden = YES;
    }

    UIImageView *fg = [self ass_nubbitForeground];
    if (fg) {
        [fg.layer removeAllAnimations];
        fg.transform = CGAffineTransformIdentity;
        fg.layer.shadowOpacity = 0.0;
        fg.layer.filters = nil;
    }

    @try {
        %orig(point, changeAlpha, animate);
    } @finally {
        sTransitionSpeedMultiplier = prev;
    }

    if (vibe) {
        [vibe updateShapeForBounds:self.bounds];
        vibe.alpha = 0.0;
        vibe.hidden = YES;
    }

    [self ass_enforceCircularShape];
}

%new
- (void)ass_enforceCircularShape {
    if ([self isFullMenuVisible]) return;

    CGFloat radius = self.bounds.size.height / 2.0;

    UIVisualEffectView *backdrop = [self ass_backdropView];
    if (backdrop) {
        backdrop.layer.cornerRadius = radius;
        backdrop.layer.cornerCurve = kCACornerCurveContinuous;
        backdrop.layer.masksToBounds = YES;
        backdrop.clipsToBounds = YES;
    }
}

%new
- (ASSHeldGlassView *)ass_glassView {
    return objc_getAssociatedObject(self, kAssGlassViewKey);
}

%new
- (ASSVibranceOverlayView *)ass_vibranceView {
    return objc_getAssociatedObject(self, kAssVibranceViewKey);
}

%new
- (ASSMenuInnerGlowView *)ass_menuGlowView {
    return objc_getAssociatedObject(self, kAssMenuGlowViewKey);
}

%new
- (UIImageView *)ass_nubbitForeground {
    Ivar iv = class_getInstanceVariable([self class], "_nubbitForeground");
    if (iv) {
        return object_getIvar(self, iv);
    }
    for (UIView *sub in self.subviews) {
        if ([sub isKindOfClass:[UIImageView class]]) return (UIImageView *)sub;
    }
    return nil;
}

%new
- (UIVisualEffectView *)ass_backdropView {
    Ivar iv = class_getInstanceVariable([self class], "_backdropView");
    if (iv) {
        return object_getIvar(self, iv);
    }
    for (UIView *sub in self.subviews) {
        if ([sub isKindOfClass:[UIVisualEffectView class]]) return (UIVisualEffectView *)sub;
    }
    return nil;
}

%new
- (void)ass_handleTouchDownAtPoint:(CGPoint)pt {
    if ([self isFullMenuVisible]) return;

    objc_setAssociatedObject(self, kAssIsHeldKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kAssStartPointKey, [NSValue valueWithCGPoint:pt], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    ASSHeldGlassView *glass = [self ass_glassView];
    ASSVibranceOverlayView *vibe = [self ass_vibranceView];
    UIImageView *fg = [self ass_nubbitForeground];
    UIVisualEffectView *backdrop = [self ass_backdropView];

    if (glass) {
        [glass.lgView applyFilters];
        [glass.lgView lgInvalidateFilterContents];
    }
    if (vibe) {
        [self bringSubviewToFront:vibe];
        [vibe forceReapplyForRegistrationRace];
    }

    if (backdrop && !objc_getAssociatedObject(self, kAssBackdropAlphaKey)) {
        objc_setAssociatedObject(self, kAssBackdropAlphaKey, @(backdrop.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    glass.hidden = NO;
    glass.alpha = 1.0;
    glass.layer.opacity = 1.0;

    if (vibe) {
        vibe.hidden = NO;
        vibe.alpha = 1.0;
        vibe.layer.opacity = 1.0;
    }
    [CATransaction commit];

    [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.76 initialSpringVelocity:0.1 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
        [glass updateShapeWithScale:1.35 stretchX:1.0 stretchY:1.0 shiftX:0 shiftY:0];
        [vibe updateShapeWithScale:1.35 stretchX:1.0 stretchY:1.0 shiftX:0 shiftY:0];
        glass.hidden = NO;
        glass.alpha = 1.0;
        if (vibe) {
            vibe.hidden = NO;
            vibe.alpha = 1.0;
        }
        glass.exposureGlowView.alpha = 0.55;

        if (fg) {
            fg.alpha = 1.0;
            fg.transform = CGAffineTransformMakeScale(1.35, 1.35);
            fg.layer.shadowColor = [UIColor whiteColor].CGColor;
            fg.layer.shadowRadius = 10.0;
            fg.layer.shadowOpacity = 1.0;
            fg.layer.shadowOffset = CGSizeZero;

            Class filterCls = NSClassFromString(@"CAFilter");
            if (filterCls) {
                id fgBright = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
                    filterCls, NSSelectorFromString(@"filterWithType:"), @"colorBrightness");
                if (fgBright) {
                    @try { [fgBright setValue:@(0.48) forKey:@"inputAmount"]; } @catch (...) {}
                    fg.layer.filters = @[fgBright];
                }
            }
        }
        if (backdrop) {
            backdrop.alpha = 0.0;
        }
    } completion:nil];
}

%new
- (void)ass_handleTouchMovedToPoint:(CGPoint)pt {
    NSNumber *heldNum = objc_getAssociatedObject(self, kAssIsHeldKey);
    if (![heldNum boolValue] || [self isFullMenuVisible]) return;

    NSValue *startVal = objc_getAssociatedObject(self, kAssStartPointKey);
    CGPoint startPt = startVal ? [startVal CGPointValue] : pt;

    CGFloat dx = pt.x - startPt.x;
    CGFloat dy = pt.y - startPt.y;
    CGFloat dist = sqrt(dx * dx + dy * dy);

    CGFloat stretchX = 1.0;
    CGFloat stretchY = 1.0;
    CGFloat shiftX = 0;
    CGFloat shiftY = 0;

    if (dist > 0.001) {
        CGFloat maxEffect = 40.0;
        CGFloat effectDist = MIN(dist * 0.40, maxEffect);

        CGFloat effectX = (dx / dist) * effectDist;
        CGFloat effectY = (dy / dist) * effectDist;

        stretchX = 1.0 + (fabs(effectX) * 0.0035);
        stretchY = 1.0 + (fabs(effectY) * 0.0070);

        shiftX = effectX * 0.45;
        shiftY = effectY * 0.45;
    }

    ASSHeldGlassView *glass = [self ass_glassView];
    ASSVibranceOverlayView *vibe = [self ass_vibranceView];
    UIImageView *fg = [self ass_nubbitForeground];

    [glass updateShapeWithScale:1.35 stretchX:stretchX stretchY:stretchY shiftX:shiftX shiftY:shiftY];
    if (vibe) {
        [vibe updateShapeWithScale:1.35 stretchX:stretchX stretchY:stretchY shiftX:shiftX shiftY:shiftY];
    }

    if (fg) {
        fg.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(1.35 * stretchX, 1.35 * stretchY), CGAffineTransformMakeTranslation(shiftX, shiftY));
    }
}

%new
- (void)ass_handleTouchEnded {
    NSNumber *heldNum = objc_getAssociatedObject(self, kAssIsHeldKey);
    if (![heldNum boolValue]) return;

    objc_setAssociatedObject(self, kAssIsHeldKey, @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    ASSHeldGlassView *glass = [self ass_glassView];
    ASSVibranceOverlayView *vibe = [self ass_vibranceView];
    UIImageView *fg = [self ass_nubbitForeground];
    UIVisualEffectView *backdrop = [self ass_backdropView];

    [UIView animateWithDuration:0.65 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.1 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
        [glass updateShapeWithScale:1.0 stretchX:1.0 stretchY:1.0 shiftX:0 shiftY:0];
        if (vibe) {
            [vibe updateShapeWithScale:1.0 stretchX:1.0 stretchY:1.0 shiftX:0 shiftY:0];
        }
        glass.alpha = 0.0;
        if (vibe) {
            vibe.alpha = 0.0;
        }
        glass.exposureGlowView.alpha = 0.0;

        if (fg) {
            fg.alpha = 1.0;
            fg.transform = CGAffineTransformIdentity;
            fg.layer.shadowOpacity = 0.0;
            fg.layer.filters = nil;
        }
        if (backdrop) {
            NSNumber *savedAlpha = objc_getAssociatedObject(self, kAssBackdropAlphaKey);
            backdrop.alpha = savedAlpha ? savedAlpha.doubleValue : 1.0;
            objc_setAssociatedObject(self, kAssBackdropAlphaKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
    } completion:^(BOOL finished) {
        if (finished) {
            if (glass.alpha == 0.0) glass.hidden = YES;
            if (vibe && vibe.alpha == 0.0) vibe.hidden = YES;
        }
    }];
}

%end

@interface HNDDisplayManager : NSObject
- (HNDRocker *)rocker;
@end

%hook HNDDisplayManager

- (void)showMenu:(BOOL)arg1 {
    if (!LGAssistiveTouchEnabled()) { %orig(arg1); return; }
    float prev = sTransitionSpeedMultiplier;
    sTransitionSpeedMultiplier = 2.0f;
    @try {
        %orig(arg1);
    } @finally {
        sTransitionSpeedMultiplier = prev;
    }
}

- (void)showCircleMenu:(BOOL)arg1 {
    if (!LGAssistiveTouchEnabled()) { %orig(arg1); return; }
    float prev = sTransitionSpeedMultiplier;
    sTransitionSpeedMultiplier = 2.0f;
    @try {
        %orig(arg1);
    } @finally {
        sTransitionSpeedMultiplier = prev;
    }
}

- (void)setNubbitMoving:(BOOL)moving {
    %orig(moving);
    if (!LGAssistiveTouchEnabled()) return;
    HNDRocker *rocker = sCurrentActiveRocker;
    if (rocker) {
        if (moving) {
            [rocker ass_handleTouchDownAtPoint:CGPointMake(rocker.bounds.size.width / 2.0, rocker.bounds.size.height / 2.0)];
        } else {
            [rocker ass_handleTouchEnded];
        }
    }
}

- (void)_repositionNubbitAfterLift:(CGPoint)point {
    %orig(point);
    if (!LGAssistiveTouchEnabled()) return;
    HNDRocker *rocker = sCurrentActiveRocker;
    if (rocker) {
        [rocker ass_handleTouchEnded];
    }
}

%end

@interface HNDRockerButton : UIView
@end

%hook HNDRockerButton

- (void)setHighlighted:(BOOL)highlighted {
    %orig(highlighted);
    if (!LGAssistiveTouchEnabled()) return;
    HNDRocker *rocker = sCurrentActiveRocker;
    if (rocker && [rocker isFullMenuVisible]) {
        if (highlighted) {
            UIVisualEffectView *backdrop = [rocker ass_backdropView];
            if (backdrop) {
                CGPoint centerInBackdrop = [self convertPoint:CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0) toView:backdrop.contentView];
                [[rocker ass_menuGlowView] handleTouchDownAtPoint:centerInBackdrop];
            }
        } else {
            [rocker ass_playMenuBounceAnimation];
            [[rocker ass_menuGlowView] handleTouchEnded];
        }
    }
}

- (void)performPress:(BOOL)sender {
    %orig(sender);
    if (!LGAssistiveTouchEnabled()) return;
    HNDRocker *rocker = sCurrentActiveRocker;
    if (rocker && [rocker isFullMenuVisible]) {
        [rocker ass_playMenuBounceAnimation];
    }
}

%end

%end

static void LGAssistiveTouchPrefsChanged(CFNotificationCenterRef center, void *observer,
                                        CFStringRef name, const void *object,
                                        CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        LGInvalidateGlassPreferenceCache();
        LGReloadPreferences();
        HNDRocker *rocker = sCurrentActiveRocker;
        if (!rocker) return;
        if (!LGAssistiveTouchEnabled()) {
            LGAssistiveTouchTeardownRocker(rocker);
        } else {
            [rocker setNeedsLayout];
        }
    });
}

static void LGAssistiveTouchRestartRequested(CFNotificationCenterRef center, void *observer,
                                            CFStringRef name, const void *object,
                                            CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        exit(0);
    });
}

%ctor {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"assistivetouchd"]) return;

    %init(LGAssistiveTouchHooks);

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        LGAssistiveTouchPrefsChanged,
        CFSTR("dylv.liquidassprefs/Reload"), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        LGAssistiveTouchRestartRequested,
        CFSTR("dylv.liquidassprefs/RestartAssistiveTouch"), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
}

