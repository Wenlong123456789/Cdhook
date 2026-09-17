#import <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <string.h>

#define MODULE_NAME "UnityFramework"
#define RVA_TargetFunc 0x1AC9570   // ⚠️ 用你实测的 FUNC START 偏移替换这里

static BOOL g_bSpeedHack = YES;
static BOOL g_bHooksInstalled = NO;
static NSInteger g_hitCount = 0;
static uintptr_t g_base = 0;

// ============ 状态按钮 ============
@interface SpeedButton : UIWindow
@end

@implementation SpeedButton
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 120, 50, 50)];
    if (self) {
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *s in UIApplication.sharedApplication.connectedScenes) {
                if (s.activationState == UISceneActivationStateForegroundActive) {
                    self.windowScene = s;
                    break;
                }
            }
        }
        self.windowLevel = UIWindowLevelAlert + 2;
        self.backgroundColor = UIColor.clearColor;
        self.hidden = NO;

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = self.bounds;
        btn.backgroundColor = [UIColor colorWithRed:0.85 green:0.25 blue:0.25 alpha:0.9];
        btn.layer.cornerRadius = 25;
        [btn setTitle:@"SPD" forState:UIControlStateNormal];
        [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [btn addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];
    }
    return self;
}

- (void)onTap {
    NSString *msg = [NSString stringWithFormat:
        @"Hook: %@\n命中: %ld\n加速: %@\n基址: 0x%lx",
        g_bHooksInstalled ? @"是" : @"否",
        (long)g_hitCount,
        g_bSpeedHack ? @"开" : @"关",
        (unsigned long)g_base];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SpeedTweak"
        message:msg
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:g_bSpeedHack ? @"关闭加速" : @"开启加速"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            g_bSpeedHack = !g_bSpeedHack;
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];

    UIWindow *key = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow) { key = w; break; }
    }
    [key.rootViewController presentViewController:alert animated:YES completion:nil];
}
@end

static SpeedButton *g_btn = nil;

// ============ Hook ============
static void (*orig_TargetFunc)(void *thiz, void *method);

static void new_TargetFunc(void *thiz, void *method) {
    g_hitCount++;

    if (g_bSpeedHack && thiz) {
        // 对应汇编: ldr x8, [x19, #0x38]  → 先取出指针
        uintptr_t ptr = *(uintptr_t *)((uintptr_t)thiz + 0x38);
        if (ptr) {
            // 对应汇编: ldr s2, [x8, #0x34] → 把这块内存改成 0.1
            float *val = (float *)(ptr + 0x34);
            *val = 0.1f;
        }
    }

    orig_TargetFunc(thiz, method);
}

static uintptr_t getModuleBase(const char *name) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (strstr(_dyld_get_image_name(i), name)) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

static void TryInstall() {
    if (g_bHooksInstalled) return;
    g_base = getModuleBase(MODULE_NAME);
    if (g_base == 0) return;

    void *addr = (void *)(g_base + RVA_TargetFunc);
    MSHookFunction(addr, (void *)new_TargetFunc, (void **)&orig_TargetFunc);
    g_bHooksInstalled = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_btn) g_btn = [SpeedButton new];
    });
}

static void OnImageAdded(const struct mach_header *mh, intptr_t slide) {
    TryInstall();
}

%ctor {
    TryInstall();
    _dyld_register_func_for_add_image(OnImageAdded);
}
