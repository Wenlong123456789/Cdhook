#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ==================== 判断目标类 ====================
static BOOL isWatermark(NSString *className) {
    return className && [className containsString:@"WatermarkOverlay"];
}

static BOOL isBasicField(NSString *className) {
    return className && [className containsString:@"BasicFieldView"];
}

// ==================== 递归处理 ====================
static void forceHandleTargets(UIView *view) {
    if (!view) return;
    
    NSArray *subs = [view.subviews copy];
    for (UIView *sub in [subs reverseObjectEnumerator]) {
        forceHandleTargets(sub);
    }
    
    NSString *name = NSStringFromClass([view class]);
    
    if (isWatermark(name)) {
        // 水印：直接删掉
        view.hidden = YES;
        view.alpha = 0.0;
        view.userInteractionEnabled = NO;
        [view removeFromSuperview];
    }
    else if (isBasicField(name)) {
        // BasicFieldView：只隐藏，不删除（防止点不动）
        view.hidden = YES;
        view.alpha = 0.0;
        view.userInteractionEnabled = NO;
        // 注意：这里故意不调用 removeFromSuperview
    }
}

// ==================== Hook ====================
%hook UIView

- (void)addSubview:(UIView *)view {
    if (!view) {
        %orig;
        return;
    }
    
    NSString *name = NSStringFromClass([view class]);
    
    if (isWatermark(name)) {
        // 水印直接不添加
        return;
    }
    
    if (isBasicField(name)) {
        // BasicFieldView 允许添加，但马上隐藏
        %orig;
        view.hidden = YES;
        view.alpha = 0.0;
        view.userInteractionEnabled = NO;
        return;
    }
    
    %orig;
}

- (void)didMoveToSuperview {
    %orig;
    
    NSString *name = NSStringFromClass([self class]);
    
    if (isWatermark(name)) {
        [self removeFromSuperview];
    }
    else if (isBasicField(name)) {
        self.hidden = YES;
        self.alpha = 0.0;
        self.userInteractionEnabled = NO;
    }
}

- (void)setHidden:(BOOL)hidden {
    NSString *name = NSStringFromClass([self class]);
    if (isWatermark(name) || isBasicField(name)) {
        %orig(YES);
        return;
    }
    %orig;
}

- (void)setAlpha:(CGFloat)alpha {
    NSString *name = NSStringFromClass([self class]);
    if (isWatermark(name) || isBasicField(name)) {
        %orig(0.0);
        return;
    }
    %orig;
}

%end

// ==================== 启动清理 ====================
%ctor {
    // 只在启动后清理几次，不再用高频定时器（减少干扰）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            forceHandleTargets(window);
        }
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            forceHandleTargets(window);
        }
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            forceHandleTargets(window);
        }
    });
}
