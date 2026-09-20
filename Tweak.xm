#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 前向声明
static void removeWatermarkInView(UIView *view);

%hook UIView

- (void)didMoveToSuperview {
    %orig;
    
    NSString *className = NSStringFromClass([self class]);
    if ([className containsString:@"WatermarkOverlay"] || 
        [className isEqualToString:@"ChinaMerchantsBank.WatermarkOverlay"]) {
        
        self.hidden = YES;
        self.alpha = 0.0;
        self.userInteractionEnabled = NO;
        // 如果想更彻底可以直接移除：
        // [self removeFromSuperview];
    }
}

%end

// 递归清理已存在的水印
static void removeWatermarkInView(UIView *view) {
    if (!view) return;
    
    NSString *className = NSStringFromClass([view class]);
    if ([className containsString:@"WatermarkOverlay"]) {
        view.hidden = YES;
        view.alpha = 0.0;
        view.userInteractionEnabled = NO;
        [view removeFromSuperview];
        return;
    }
    
    // 用 copy 防止边遍历边修改崩溃
    NSArray *subs = [view.subviews copy];
    for (UIView *sub in subs) {
        removeWatermarkInView(sub);
    }
}

%ctor {
    // 延迟扫描一次，清理已经存在的水印
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            removeWatermarkInView(window);   // ← 这里直接调用，不要加 self
        }
    });
    
    // 可选：每 3 秒再扫一次（防止页面切换后水印重新出现）
    /*
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                removeWatermarkInView(window);
            }
        }];
    });
    */
}
