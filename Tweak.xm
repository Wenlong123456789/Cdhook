#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 前向声明
static void removeTargetViewsInView(UIView *view);

%hook UIView

- (void)didMoveToSuperview {
    %orig;
    
    NSString *className = NSStringFromClass([self class]);
    
    // 1. 水印
    if ([className containsString:@"WatermarkOverlay"] ||
        [className isEqualToString:@"ChinaMerchantsBank.WatermarkOverlay"]) {
        
        self.hidden = YES;
        self.alpha = 0.0;
        self.userInteractionEnabled = NO;
    }
    
    // 2. 悬浮工具栏
    if ([className containsString:@"_UIFloatingBarContainerView"] ||
        [className containsString:@"FloatingBarContainerView"] ||
        [className containsString:@"FloatingBarHostingView"]) {
        
        self.hidden = YES;
        self.alpha = 0.0;
        self.userInteractionEnabled = NO;
    }
    
    // 3. 触摸穿透视图
    if ([className containsString:@"_UITouchPassthroughView"]) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
    
    // 4. BasicFieldView
    if ([className containsString:@"BasicFieldView"] ||
        [className isEqualToString:@"ChinaMerchantsBank.BasicFieldView"]) {
        
        self.hidden = YES;
        self.alpha = 0.0;
        self.userInteractionEnabled = NO;
    }
}

%end

// 递归清理已经存在的目标视图
static void removeTargetViewsInView(UIView *view) {
    if (!view) return;
    
    NSString *className = NSStringFromClass([view class]);
    
    BOOL shouldHide = NO;
    
    if ([className containsString:@"WatermarkOverlay"] ||
        [className isEqualToString:@"ChinaMerchantsBank.WatermarkOverlay"]) {
        shouldHide = YES;
    }
    
    if ([className containsString:@"_UIFloatingBarContainerView"] ||
        [className containsString:@"FloatingBarContainerView"] ||
        [className containsString:@"FloatingBarHostingView"]) {
        shouldHide = YES;
    }
    
    if ([className containsString:@"_UITouchPassthroughView"]) {
        shouldHide = YES;
    }
    
    if ([className containsString:@"BasicFieldView"] ||
        [className isEqualToString:@"ChinaMerchantsBank.BasicFieldView"]) {
        shouldHide = YES;
    }
    
    if (shouldHide) {
        view.hidden = YES;
        view.alpha = 0.0;
        view.userInteractionEnabled = NO;
        // 如果想更彻底可以取消下面注释
        // [view removeFromSuperview];
        return;
    }
    
    // 用 copy 防止边遍历边修改崩溃
    NSArray *subs = [view.subviews copy];
    for (UIView *sub in subs) {
        removeTargetViewsInView(sub);
    }
}

%ctor {
    // 延迟 1.5 秒扫描一次
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            removeTargetViewsInView(window);
        }
    });
    
    // 可选：每 3 秒再扫一次（防止切换页面后重新出现）
    /*
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                removeTargetViewsInView(window);
            }
        }];
    });
    */
}
