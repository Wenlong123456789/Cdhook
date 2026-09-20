#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ==================== 判断是否是水印 ====================
static BOOL isWatermark(NSString *className) {
    return className && [className containsString:@"WatermarkOverlay"];
}

// ==================== 递归删除水印 ====================
static void forceRemoveWatermark(UIView *view) {
    if (!view) return;
    
    NSArray *subs = [view.subviews copy];
    for (UIView *sub in [subs reverseObjectEnumerator]) {
        forceRemoveWatermark(sub);
    }
    
    if (isWatermark(NSStringFromClass([view class]))) {
        view.hidden = YES;
        view.alpha = 0.0;
        view.userInteractionEnabled = NO;
        [view removeFromSuperview];
    }
}

// ==================== Hook ====================
%hook UIView

- (void)addSubview:(UIView *)view {
    if (view && isWatermark(NSStringFromClass([view class]))) {
        // 水印直接不添加
        return;
    }
    %orig;
}

- (void)didMoveToSuperview {
    %orig;
    if (isWatermark(NSStringFromClass([self class]))) {
        [self removeFromSuperview];
    }
}

- (void)setHidden:(BOOL)hidden {
    if (isWatermark(NSStringFromClass([self class]))) {
        %orig(YES);
        return;
    }
    %orig;
}

- (void)setAlpha:(CGFloat)alpha {
    if (isWatermark(NSStringFromClass([self class]))) {
        %orig(0.0);
        return;
    }
    %orig;
}

%end

// ==================== 启动后清理几次 ====================
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            forceRemoveWatermark(window);
        }
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            forceRemoveWatermark(window);
        }
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            forceRemoveWatermark(window);
        }
    });
}
