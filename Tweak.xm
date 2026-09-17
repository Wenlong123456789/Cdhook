#import <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <string.h>

#define MODULE_NAME "UnityFramework"
#define RVA_TargetFunc 0x1AC9570

// 目标函数开头前 8 字节的机器码特征(来自你截图: sub sp,sp,#0xd0 ; stp d11,d10,...)
// 用来校验这次装的偏移是不是真的对准了同一个函数,不对就不装,避免把别的指令覆盖坏
static const uint8_t kExpectedProlog[8] = {
    0xff, 0x43, 0x03, 0xd1,   // sub sp, sp, #0xd0
    0xeb, 0x2b, 0x09, 0x6d    // stp d11, d10, [sp, #0x90]
};

static BOOL g_bSpeedHack = NO;       // ⚠️ 默认关闭,手动开
static BOOL g_bHooksInstalled = NO;
static BOOL g_bPrologMatched = NO;
static BOOL g_bModuleFound = NO;
static NSInteger g_hitCount = 0;
static uintptr_t g_base = 0;
static NSString *g_lastError = @"";

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
        @"模块找到: %@\n特征码匹配: %@\nHook已装: %@\n命中次数: %ld\n加速: %@\n基址: 0x%lx\n目标地址: 0x%lx\n错误信息: %@",
        g_bModuleFound ? @"是" : @"否",
        g_bPrologMatched ? @"是" : @"否 (偏移可能不对!)",
        g_bHooksInstalled ? @"是" : @"否",
        (long)g_hitCount,
        g_bSpeedHack ? @"开" : @"关",
        (unsigned long)g_base,
        (unsigned long)(g_base ? g_base + RVA_TargetFunc : 0),
        g_lastError];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SpeedTweak 状态"
        message:msg
        preferredStyle:UIAlertControllerStyleAlert];

    if (g_bHooksInstalled) {
        [alert addAction:[UIAlertAction actionWithTitle:g_bSpeedHack ? @"关闭加速" : @"开启加速"
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *a) {
                g_bSpeedHack = !g_bSpeedHack;
            }]];
    }
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

    // 手动开关关闭时,只统计命中次数,不碰任何内存 —— 这样至少能确认 hook 本身没让游戏崩
    if (g_bSpeedHack && thiz) {
        uintptr_t ptr = *(uintptr_t *)((uintptr_t)thiz + 0x38);
        // 基本的野指针防护:非空 且 地址看起来像正常堆地址(iOS 上用户态地址一般 >= 0x100000000)
        if (ptr > 0x100000000) {
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

static void ShowInjectStatus(NSString *title, NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *key = nil;
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (w.isKeyWindow) { key = w; break; }
        }
        if (!key.rootViewController) return; // 界面还没起来就先不弹,避免弹窗本身导致崩溃

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
            message:msg
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [key.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

static void TryInstall() {
    if (g_bHooksInstalled) return;

    g_base = getModuleBase(MODULE_NAME);
    if (g_base == 0) {
        g_lastError = @"未找到 UnityFramework 模块";
        return;
    }
    g_bModuleFound = YES;

    void *addr = (void *)(g_base + RVA_TargetFunc);

    // 校验特征码,防止装到错误位置把指令覆盖坏导致必崩
    if (memcmp((void *)addr, kExpectedProlog, sizeof(kExpectedProlog)) == 0) {
        g_bPrologMatched = YES;
    } else {
        g_bPrologMatched = NO;
        g_lastError = @"特征码不匹配,偏移可能已失效(游戏更新/版本不同),已跳过安装避免崩溃";
        ShowInjectStatus(@"SpeedTweak 未安装",
            [NSString stringWithFormat:@"%@\n基址: 0x%lx\n目标地址: 0x%lx",
                g_lastError, (unsigned long)g_base, (unsigned long)addr]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!g_btn) g_btn = [SpeedButton new];
        });
        return;
    }

    @try {
        MSHookFunction(addr, (void *)new_TargetFunc, (void **)&orig_TargetFunc);
        g_bHooksInstalled = YES;
    } @catch (NSException *e) {
        g_lastError = [NSString stringWithFormat:@"MSHookFunction 异常: %@", e.reason];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_btn) g_btn = [SpeedButton new];
    });

    // 装好后延迟 2 秒自动弹一次状态,方便你不用点按钮就能看结果
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ShowInjectStatus(@"SpeedTweak 注入状态",
            [NSString stringWithFormat:
                @"模块: %@\n特征码匹配: %@\nHook已装: %@\n命中次数(2秒内): %ld\n基址: 0x%lx",
                g_bModuleFound ? @"已找到" : @"未找到",
                g_bPrologMatched ? @"匹配" : @"不匹配",
                g_bHooksInstalled ? @"是" : @"否",
                (long)g_hitCount,
                (unsigned long)g_base]);
    });
}

static void OnImageAdded(const struct mach_header *mh, intptr_t slide) {
    TryInstall();
}

%ctor {
    TryInstall();
    _dyld_register_func_for_add_image(OnImageAdded);
}
