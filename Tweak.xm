#import <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <string.h>

#define MODULE_NAME "UnityFramework"
#define RVA_TargetFunc 0x1AC9570

// 目标函数开头 8 字节特征码,防止偏移错位时把别的指令覆盖坏
static const uint8_t kExpectedProlog[8] = {
    0xff, 0x43, 0x03, 0xd1,   // sub sp, sp, #0xd0
    0xeb, 0x2b, 0x09, 0x6d    // stp d11, d10, [sp, #0x90]
};

static BOOL g_bSpeedHack = NO;       // 默认关闭,靠悬浮按钮手动开
static BOOL g_bHooksInstalled = NO;
static BOOL g_bPrologMatched = NO;
static BOOL g_bModuleFound = NO;
static NSInteger g_hitCount = 0;
static uintptr_t g_base = 0;
static NSString *g_lastError = @"";

// ============ 沙盒内日志,不再碰 /var/mobile ============
static void LogStep(NSString *step) {
    @try {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *dir = paths.firstObject;
        if (!dir) return;
        NSString *path = [dir stringByAppendingPathComponent:@"speedtweak.log"];

        NSString *line = [NSString stringWithFormat:@"%@ | %@\n", [NSDate date], step];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:path];
        }
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    } @catch (...) {
        // 日志本身绝不能拖垮 App
    }
}

// ============ 悬浮状态按钮 ============
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
        @"模块找到: %@\n特征码匹配: %@\nHook已装: %@\n命中次数: %ld\n加速: %@\n基址: 0x%lx\n错误: %@",
        g_bModuleFound ? @"是" : @"否",
        g_bPrologMatched ? @"是" : @"否",
        g_bHooksInstalled ? @"是" : @"否",
        (long)g_hitCount,
        g_bSpeedHack ? @"开" : @"关",
        (unsigned long)g_base,
        g_lastError];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SpeedTweak"
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

// ============ Hook 逻辑 ============
static void (*orig_TargetFunc)(void *thiz, void *method);

static void new_TargetFunc(void *thiz, void *method) {
    g_hitCount++;

    if (g_bSpeedHack && thiz) {
        uintptr_t ptr = *(uintptr_t *)((uintptr_t)thiz + 0x38);
        if (ptr > 0x100000000) {   // 简单的野指针防护
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
        @try {
            UIWindow *key = nil;
            for (UIWindow *w in UIApplication.sharedApplication.windows) {
                if (w.isKeyWindow) { key = w; break; }
            }
            if (!key.rootViewController) return;

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                message:msg
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [key.rootViewController presentViewController:alert animated:YES completion:nil];
        } @catch (...) {}
    });
}

static void DoInstall() {
    @try {
        if (g_bHooksInstalled) return;

        LogStep(@"DoInstall 开始");

        g_base = getModuleBase(MODULE_NAME);
        if (g_base == 0) {
            g_lastError = @"未找到 UnityFramework 模块";
            LogStep(g_lastError);
            return;
        }
        g_bModuleFound = YES;
        LogStep([NSString stringWithFormat:@"找到模块, 基址=0x%lx", (unsigned long)g_base]);

        void *addr = (void *)(g_base + RVA_TargetFunc);
        LogStep([NSString stringWithFormat:@"目标地址=0x%lx", (unsigned long)addr]);

        if (memcmp((void *)addr, kExpectedProlog, sizeof(kExpectedProlog)) != 0) {
            g_bPrologMatched = NO;
            g_lastError = @"特征码不匹配,偏移可能已失效,已跳过安装";
            LogStep(g_lastError);
            ShowInjectStatus(@"SpeedTweak 未安装", g_lastError);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!g_btn) g_btn = [SpeedButton new];
            });
            return;
        }
        g_bPrologMatched = YES;
        LogStep(@"特征码匹配");

        MSHookFunction(addr, (void *)new_TargetFunc, (void **)&orig_TargetFunc);
        g_bHooksInstalled = YES;
        LogStep(@"MSHookFunction 成功");

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!g_btn) g_btn = [SpeedButton new];
        });

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ShowInjectStatus(@"SpeedTweak 注入状态",
                [NSString stringWithFormat:
                    @"模块: %@\n特征码匹配: %@\nHook已装: %@\n命中次数(2秒内): %ld",
                    g_bModuleFound ? @"已找到" : @"未找到",
                    g_bPrologMatched ? @"匹配" : @"不匹配",
                    g_bHooksInstalled ? @"是" : @"否",
                    (long)g_hitCount]);
        });
    } @catch (NSException *e) {
        g_lastError = [NSString stringWithFormat:@"DoInstall 异常: %@", e.reason];
        LogStep(g_lastError);
    }
}

%ctor {
    @try {
        LogStep(@"===== ctor 启动 =====");
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note) {
                static BOOL done = NO;
                if (done) return;
                done = YES;
                @try {
                    LogStep(@"App 已激活, 开始安装 hook");
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        DoInstall();
                    });
                } @catch (NSException *e) {
                    LogStep([NSString stringWithFormat:@"激活回调异常: %@", e.reason]);
                }
            }];
    } @catch (...) {
        // ctor 阶段任何异常都不能让 App 崩
    }
}
