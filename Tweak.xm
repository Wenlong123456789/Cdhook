#import <UIKit/UIKit.h>
#import <objc/runtime.h>

%hook UIView

// 当任何 UIView 被添加到父视图时检查
- (void)didMoveToSuperview {
    %orig;
    
    // 类名匹配 WatermarkOverlay
    NSString *className = NSStringFromClass([self class]);
    if ([className containsString:@"WatermarkOverlay"] || 
        [className isEqualToString:@"ChinaMerchantsBank.WatermarkOverlay"]) {
        
        // 方式1：直接隐藏
        self.hidden = YES;
        self.alpha = 0;
        self.userInteractionEnabled = NO;
        
        // 方式2：从父视图移除（更彻底）
        // [self removeFromSuperview];
        
        // 方式3：清空内容（防止重新显示）
        // for (UIView *sub in self.subviews) {
        //     [sub removeFromSuperview];
        // }
    }
}

%end

// 额外保险：Hook 初始化方法（如果上面不够用）
%hook NSObject

+ (id)alloc {
    id obj = %orig;
    NSString *className = NSStringFromClass([self class]);
    if ([className containsString:@"WatermarkOverlay"]) {
        // 可以在这里做标记或直接返回 nil（不推荐，容易崩）
    }
    return obj;
}

%end

%ctor {
    // 延迟执行一次全窗口扫描，清理已经存在的水印
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            [self removeWatermarkInView:window];
        }
    });
}

// 递归清理已有水印的辅助方法
static void removeWatermarkInView(UIView *view) {
    if (!view) return;
    
    NSString *className = NSStringFromClass([view class]);
    if ([className containsString:@"WatermarkOverlay"]) {
        view.hidden = YES;
        view.alpha = 0;
        [view removeFromSuperview];
        return;
    }
    
    for (UIView *sub in [view.subviews copy]) {
        removeWatermarkInView(sub);
    }
}
