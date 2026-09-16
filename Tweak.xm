#import <substrate.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

// ============ 基础配置 ============
#define MODULE_NAME "UnityFramework"

// 暂时保留，但当前不会使用
#define RVA_StartCoolDown  0x269D08C
#define RVA_EndCoolDown    0x269EA7C

#define OFFSET_fCurCoolDownTimeLeft  0x10
#define OFFSET_fMaxCoolDownTime      0x14
#define OFFSET_bStartCD              0x80
#define OFFSET_bCanUse               0x81

// ============ 全局状态 ============
static BOOL g_bResetCDToZero = NO;
static BOOL g_bHooksInstalled = NO;
static NSInteger g_hookHitCount_Start = 0;
static NSInteger g_hookHitCount_End   = 0;
static int32_t   g_lastCurCD = -1;
static int32_t   g_lastMaxCD = -1;
static NSMutableString *g_lastModuleListText = nil;

// ============ 弹窗容器（已修复触摸穿透） ============
@interface CDAlertHostWindow : UIWindow
@end

@implementation CDAlertHostWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *view = [super hitTest:point withEvent:event];
    if (view == self || view == self.rootViewController.view) {
        return nil;
    }
    return view;
}
@end

static CDAlertHostWindow *g_alertHostWindow = nil;
static UIViewController *g_alertHostVC = nil;

static UIViewController *AlertHostController() {
    if (g_alertHostWindow) return g_alertHostVC;

    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                g_alertHostWindow = [[CDAlertHostWindow alloc] initWithWindowScene:scene];
                break;
            }
        }
    }
    if (!g_alertHostWindow) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        g_alertHostWindow = [[CDAlertHostWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        #pragma clang diagnostic pop
    }

    g_alertHostVC = [[UIViewController alloc] init];
    g_alertHostVC.view.backgroundColor = [UIColor clearColor];
    g_alertHostVC.view.userInteractionEnabled = NO;

    g_alertHostWindow.rootViewController = g_alertHostVC;
    g_alertHostWindow.windowLevel = UIWindowLevelAlert + 1;
    g_alertHostWindow.backgroundColor = [UIColor clearColor];
    g_alertHostWindow.hidden = NO;

    return g_alertHostVC;
}

static void ShowAlertWithCopy(NSString *title, NSString *message, NSString *copyText) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = AlertHostController();
        if (!top) return;

        top.view.userInteractionEnabled = YES;

        if (top.presentedViewController) {
            [top dismissViewControllerAnimated:NO completion:nil];
        }

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                         message:message
                                                                  preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"复制完整日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [UIPasteboard generalPasteboard].string = copyText ?: message;
            UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"已复制"
                                                                               message:@"完整日志已复制到剪贴板"
                                                                        preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [top presentViewController:confirm animated:YES completion:nil];
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            top.view.userInteractionEnabled = NO;
        }]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

static void ShowAlert(NSString *title, NSString *message) {
    ShowAlertWithCopy(title, message, message);
}

// ============ 悬浮按钮 ============
@interface CDStatusButton : UIWindow
@end

@implementation CDStatusButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 80, 60, 60)];
    if (self) {
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    self.windowScene = scene;
                    break;
                }
            }
        }

        self.windowLevel = UIWindowLevelAlert + 2;
        self.backgroundColor = [UIColor clearColor];
        self.hidden = NO;

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(0, 0, 60, 60);
        btn.backgroundColor = [UIColor colorWithRed:0.1 green:0.6 blue:0.1 alpha:0.85];
        btn.layer.cornerRadius = 30;
        [btn setTitle:@"CD" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [btn addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onDrag:)];
        [btn addGestureRecognizer:pan];

        [self addSubview:btn];
    }
    return self;
}

- (void)onDrag:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:self];
}

- (void)onTap {
    NSString *msg = [NSString stringWithFormat:
        @"Hook已安装: %@\n\nStartCoolDown 命中: %ld\nEndCoolDown 命中: %ld\n\n最近curCD: %d\n最近maxCD: %d\n\n清零CD开关: %@",
        g_bHooksInstalled ? @"是（当前无实际Hook）" : @"否",
        (long)g_hookHitCount_Start, (long)g_hookHitCount_End,
        g_lastCurCD, g_lastMaxCD,
        g_bResetCDToZero ? @"开启" : @"关闭"];

    UIViewController *top = AlertHostController();
    if (!top) return;

    top.view.userInteractionEnabled = YES;

    if (top.presentedViewController) {
        [top dismissViewControllerAnimated:NO completion:nil];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CDTweak 状态"
                                                                     message:msg
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:g_bResetCDToZero ? @"关闭清零" : @"开启清零"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        g_bResetCDToZero = !g_bResetCDToZero;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制模块列表" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = g_lastModuleListText ?: @"(暂无数据)";
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        top.view.userInteractionEnabled = NO;
    }]];
    [top presentViewController:alert animated:YES completion:nil];
}

@end

static CDStatusButton *g_statusButton = nil;

// ============ 获取模块基址 ============
static uintptr_t getModuleBaseAccurate(const char *moduleName) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, moduleName)) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

static NSString *ListAllModules() {
    NSMutableString *result = [NSMutableString string];
    [result appendFormat:@"共 %u 个已加载模块:\n\n", _dyld_image_count()];
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        NSString *ns = [NSString stringWithUTF8String:name];
        [result appendFormat:@"%@\n", [ns lastPathComponent]];
    }
    return result;
}

// ============ 原函数指针（当前未使用） ============
static void (*orig_StartCoolDown)(void *thiz, int32_t nCur, int32_t nMax, void *method);
static void (*orig_EndCoolDown)(void *thiz, void *method);

// ============ Hook 实现（当前未使用，加 __unused 避免编译报错） ============
__attribute__((unused))
static void new_StartCoolDown(void *thiz, int32_t nCur, int32_t nMax, void *method) {
    g_hookHitCount_Start++;
    g_lastCurCD = nCur;
    g_lastMaxCD = nMax;

    if (g_bResetCDToZero) {
        nCur = 0;
    }

    if (orig_StartCoolDown) {
        orig_StartCoolDown(thiz, nCur, nMax, method);
    }

    if (g_bResetCDToZero && thiz) {
        *(float *)((uintptr_t)thiz + OFFSET_fCurCoolDownTimeLeft) = 0.0f;
        *(bool *)((uintptr_t)thiz + OFFSET_bStartCD) = false;
        *(bool *)((uintptr_t)thiz + OFFSET_bCanUse)  = true;
    }
}

__attribute__((unused))
static void new_EndCoolDown(void *thiz, void *method) {
    g_hookHitCount_End++;

    if (orig_EndCoolDown) {
        orig_EndCoolDown(thiz, method);
    }

    if (g_bResetCDToZero && thiz) {
        *(float *)((uintptr_t)thiz + OFFSET_fCurCoolDownTimeLeft) = 0.0f;
        *(bool *)((uintptr_t)thiz + OFFSET_bStartCD) = false;
        *(bool *)((uintptr_t)thiz + OFFSET_bCanUse)  = true;
    }
}

// ============ 安装 Hook（当前已全部关闭） ============
static void TryInstallHooks(void) {
    if (g_bHooksInstalled) return;

    uintptr_t base = getModuleBaseAccurate(MODULE_NAME);
    if (base == 0) return;

    // ========== 当前已关闭所有 Hook，只验证是否还会闪退 ==========
    /*
    void *addr_start = (void *)(base + RVA_StartCoolDown);
    MSHookFunction(addr_start, (void *)new_StartCoolDown, (void **)&orig_StartCoolDown);

    void *addr_end = (void *)(base + RVA_EndCoolDown);
    MSHookFunction(addr_end, (void *)new_EndCoolDown, (void **)&orig_EndCoolDown);
    */

    g_bHooksInstalled = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        ShowAlert(@"CDTweak 已加载（当前无任何Hook）",
                  [NSString stringWithFormat:@"基址: 0x%lx\n\n请先进副本测试是否还会闪退", (unsigned long)base]);
        if (!g_statusButton) {
            g_statusButton = [[CDStatusButton alloc] init];
        }
    });
}

static void OnImageAdded(const struct mach_header *mh, intptr_t vmaddr_slide) {
    TryInstallHooks();
}

%ctor {
    TryInstallHooks();
    _dyld_register_func_for_add_image(OnImageAdded);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!g_bHooksInstalled) {
            NSString *allModules = ListAllModules();
            g_lastModuleListText = [allModules mutableCopy];
            ShowAlertWithCopy(@"CDTweak: 未找到 UnityFramework",
                               @"点下方按钮复制模块列表",
                               allModules);
        }
    });
}
