#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 前向声明
static void removeTargetViewsInView(UIView *view);
static BOOL isTargetClass(NSString *className);

// 判断是否是目标类
static BOOL isTargetClass(NSString *className) {
    if (!className) return NO;
    
    // 水印
    if ([className containsString:@"WatermarkOverlay"] ||
        [className isEqualToString:@"ChinaMerchantsBank.WatermarkOverlay"]) {
        return YES;
    }
    
    // 悬浮工具栏
    if ([className containsString:@"_UIFloatingBarContainerView"] ||
        [className containsString:@"FloatingBarContainerView"] ||
        [className containsString:@"FloatingBarHostingView"]) {
        return YES;
    }
    
    // 触摸穿透视图
    if ([className containsString:@"_UITouchPassthroughView"]) {
        return YES;
    }
    
    // BasicFieldView（图一）
    if ([className containsString:@"BasicFieldView"] ||
        [className isEqualToString:@"ChinaMerchantsBank.BasicFieldView"]) {
        return YES;
    }
    
    return NO;
}

%hook UIView

// 1. 添加到父视图时立刻处理
- (void)didMoveToSuperview {
    %orig;
    
    NSString *className = NSStringFromClass([self class]);
    if (isTargetClass(className)) {
        // 直接移除，比 hidden 更彻底
        [self removeFromSuperview];
    }
}

// 2. 防止被重新显示
- (void)setHidden:(BOOL)hidden {
    NSString *className = NSStringFromClass([self class]);
    if (isTargetClass(className)) {
        %orig(YES);   // 强制隐藏
        return;
    }
    %orig;
}

- (void)setAlpha:(CGFloat)alpha {
    NSString *className = NSStringFromClass([self class]);
    if (isTargetClass(className)) {
        %orig(0.0);   // 强制透明
        return;
    }
    %orig;
}

// 3. 布局时再检查一次
- (void)layoutSubviews {
    %orig;
    
    NSString *className = NSStringFromClass([self class]);
    if (isTargetClass(className)) {
        self.hidden = YES;
        self.alpha = 0.0;
        [self removeFromSuperview];
    }
}

%end

// 递归清理
static void removeTargetViewsInView(UIView *view) {
    if (!view) return;
    
    NSString *className = NSStringFromClass([view class]);
    
    if (isTargetClass(className)) {
        view.hidden = YES;
        view.alpha = 0.0;
        [view removeFromSuperview];
        return;
    }
    
    NSArray *subs = [view.subviews copy];
    for (UIView *sub in subs) {
        removeTargetViewsInView(sub);
    }
}

%ctor {
    // 启动后延迟清理一次
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            removeTargetViewsInView(window);
        }
    });
    
    // 持续清理（每 2 秒扫一次，防止页面切换后重新出现）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                removeTargetViewsInView(window);
            }
        }];
    });
}
