#import <UIKit/UIKit.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

static NSHashTable<UIView *> *sAppLibraryPods;
static const void *kAppLibSavedHiddenKey = &kAppLibSavedHiddenKey;

#pragma mark - search pill

static BOOL isAppLibrarySearchMaterial(UIView *material) {
    static Class materialClass = Nil, searchClass = Nil;
    if (!materialClass) materialClass = NSClassFromString(@"MTMaterialView");
    if (!searchClass) searchClass = NSClassFromString(@"SBHSearchTextField");
    if (!searchClass) return NO;
    for (UIView *view = material.superview; view; view = view.superview) {
        if ([view isKindOfClass:searchClass]) return YES;
        if (materialClass && [view isKindOfClass:materialClass]) return NO;
    }
    return NO;
}

#pragma mark - category pods

static void restoreAppLibraryPodHidden(UIView *pod) {
    NSNumber *savedHidden = objc_getAssociatedObject(pod, kAppLibSavedHiddenKey);
    if (!savedHidden) return;
    objc_setAssociatedObject(pod, kAppLibSavedHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    pod.hidden = savedHidden.boolValue;
}

static void injectAppLibraryPod(UIView *pod) {
    if (!pod.window || !lgHostEnabled(@"AppLibrary")) {
        LGRemoveGlassFromMaterial(pod, kGlassKey);
        restoreAppLibraryPodHidden(pod);
        return;
    }
    CGRect bounds = pod.bounds;
    if (CGRectGetWidth(bounds) < 2.0 || CGRectGetHeight(bounds) < 2.0) return;
    if (!sAppLibraryPods) sAppLibraryPods = [NSHashTable weakObjectsHashTable];
    [sAppLibraryPods addObject:pod];
    CGFloat radius = pod.layer.cornerRadius > 0.0
        ? pod.layer.cornerRadius
        : 20.0;
    LGInstallRegisteredGlassInMaterial(pod, kGlassKey, @"AppLibrary",
                                       UIEdgeInsetsZero, radius, nil);
}

%hook SBHLibraryCategoryPodBackgroundView
- (void)didMoveToWindow {
    %orig;
    injectAppLibraryPod((UIView *)self);
}
- (void)layoutSubviews {
    %orig;
    injectAppLibraryPod((UIView *)self);
}
- (void)setHidden:(BOOL)hidden {
    UIView *self_ = (UIView *)self;
    if (LGMaterialHasGlass(self_, kGlassKey)) {
        objc_setAssociatedObject(self_, kAppLibSavedHiddenKey, @(hidden),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        hidden = YES;
    }
    %orig(hidden);
}
%end

%ctor {
    %init;
    LGRegisterMaterialHost(@"AppLibSearch", 90, ^BOOL(UIView *material) {
        return isAppLibrarySearchMaterial(material);
    }, UIEdgeInsetsZero, ^CGFloat(UIView *material) {
        return CGRectGetHeight(material.bounds) * 0.5;
    }, nil, nil);
    lgObservePreferenceReload(^{
        for (UIView *pod in [sAppLibraryPods allObjects]) {
            injectAppLibraryPod(pod);
        }
    });
}
