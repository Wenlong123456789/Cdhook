#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ==================== 判断目标类 ====================
static BOOL isTargetClass(NSString *className) {
    if (!className || className.length == 0) return NO;
    
    // 1. 水印
    if ([className containsString:@"WatermarkOverlay"]) return YES;
    
    // 2. BasicFieldView
    if ([className containsString:@"BasicFieldView"]) return YES;
    
    return NO;
}

static BOOL isTargetView(UIView *view) {
    if (!view) return NO;
    return isTargetClass(NSStringFromClass([view class]));
}

// ==================== 递归强制删除 ====================
static void forceRemoveTargets(UIView *view) {
    if (!view) return;
    
    // 先处理子视图（从后往前删更安全）
    NSArray *subs = [view.subviews copy];
    for (UIView *sub in [subs reverseObjectEnumerator]) {
        forceRemoveTargets(sub);
    }
    
    if (isTargetView(view)) {
        view.hidden = YES;
        view.alpha = 0.0;
        view.userInteractionEnabled = NO;
        [view removeFromSuperview];
    }
}

// ==================== Hook addSubview 从源头拦截 ====================
%hook UIView

- (void)addSubview:(UIView *)view {
    if (isTargetView(view)) {
        // 直接不添加
        return;
    }
    %orig;
}

- (void)insertSubview:(UIView *)view atIndex:(NSInteger)index {
    if (isTargetView(view)) {
        return;
    }
    %orig;
}

- (void)insertSubview:(UIView *)view aboveSubview:(UIView *)siblingSubview {
    if (isTargetView(view)) {
        return;
    }
    %orig;
}

- (void)insertSubview:(UIView *)view belowSubview:(UIView *)siblingSubview {
    if (isTargetView(view)) {
        return;
    }
    %orig;
}

- (void)didMoveToSuperview {
    %orig;
    if (isTargetView(self)) {
        [self removeFromSuperview];
    }
}

- (void)setHidden:(BOOL)hidden {
    if (isTargetView(self)) {
        %orig(YES);
        return;
    }
    %orig;
}

- (void)setAlpha:(CGFloat)alpha {
    if (isTargetView(self)) {
        %orig(0.0);
        return;
    }
    %orig;
}

- (void)layoutSubviews {
    %orig;
    if (isTargetView(self)) {
        self.hidden = YES;
        self.alpha = 0.0;
        [self removeFromSuperview];
    }
}

%end

// ==================== 启动后持续清理 ====================
%ctor {
    // 1.5 秒后清理一次
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            forceRemoveTargets(window);
        }
    });
    
    // 每 1.5 秒持续清理（防止页面切换重新创建）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer * _Nonnull timer) {
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                forceRemoveTargets(window);
            }
        }];
    });
}
