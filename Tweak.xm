#import <substrate.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

// ============ 基础配置 ============
#define MODULE_NAME "UnityFramework"

#define RVA_StartCoolDown_v3  0x27EBD00   // StartCoolDown(Single, Single)
#define RVA_EndCoolDown       0x269EA7C   // EndCoolDown()
#define RVA_IsInCoolDown      0x272906C   // IsInCoolDown()

#define OFFSET_fCurCoolDownTimeLeft  0x10
#define OFFSET_fMaxCoolDownTime      0x14

// ============ 全局状态 ============
static BOOL g_bResetCDToZero = NO;
static BOOL g_bHooksInstalled = NO;
static NSInteger g_hookHitCount_Start = 0;
static NSInteger g_hookHitCount_End   = 0;
static NSInteger g_hookHitCount_IsIn  = 0;
static float     g_lastCurCD = -1;
static float     g_lastMaxCD = -1;
static NSMutableString *g_lastModuleListText = nil;

// ============ 工具：找当前最顶层的ViewController ============
static UIViewController *TopMostController() {
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in scene.windows) {
                    if (window.isKeyWindow) { keyWindow = window; break; }
                }
            }
        }
    }
    if (!keyWindow) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = [UIApplication sharedApplication].keyWindow;
        #pragma clang diagnostic pop
    }
    UIViewController *top = keyWindow.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    return top;
}

// ============ 弹窗工具函数（带一键复制按钮） ============
static void ShowAlertWithCopy(NSString *title, NSString *message, NSString *copyText) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = TopMostController();
        if (!top) return;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                         message:message
                                                                  preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"复制完整日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [UIPasteboard generalPasteboard].string = copyText ?: message;

            UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"已复制"
                                                                               message:@"完整日志已复制到剪贴板，可以粘贴到备忘录/微信发出来"
                                                                        preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [top presentViewController:confirm animated:YES completion:nil];
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

static void ShowAlert(NSString *title, NSString *message) {
    ShowAlertWithCopy(title, message, message);
}

// ============ 悬浮小按钮：点一下弹出当前Hook状态 ============
@interface CDStatusButton : UIWindow
@end

@implementation CDStatusButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 80, 60, 60)];
    if (self) {
        // 关键修复：显式绑定到当前活跃的windowScene，但不调用makeKeyAndVisible，
        // 避免抢走游戏主窗口的KeyWindow身份（这会导致渲染/输入异常甚至崩溃）
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    self.windowScene = scene;
                    break;
                }
            }
        }

        self.windowLevel = UIWindowLevelAlert + 1;
        self.backgroundColor = [UIColor clearColor];
        self.hidden = NO; // 只是显示出来，不抢KeyWindow

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
        @"Hook已安装: %@\n\nStartCoolDown 命中: %ld\nEndCoolDown 命中: %ld\nIsInCoolDown 命中: %ld\n\n最近curCD: %.2f\n最近maxCD: %.2f\n\n清零CD开关: %@",
        g_bHooksInstalled ? @"是" : @"否(模块未找到)",
        (long)g_hookHitCount_Start, (long)g_hookHitCount_End, (long)g_hookHitCount_IsIn,
        g_lastCurCD, g_lastMaxCD,
        g_bResetCDToZero ? @"开启" : @"关闭"];

    UIViewController *top = TopMostController();
    if (!top) return;

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
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

@end

static CDStatusButton *g_statusButton = nil;

// ============ 获取模块基址 ============
static uintptr_t getModuleBaseAccurate(const char *moduleName) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, moduleName)) {
            const struct mach_header *header = _dyld_get_image_header(i);
            return (uintptr_t)header;
        }
    }
    return 0;
}

// 列出所有已加载模块名（完整版，不截断，供复制）
static NSString *ListAllModules() {
    NSMutableString *result = [NSMutableString string];
    [result appendFormat:@"共 %u 个已加载模块:\n\n", _dyld_image_count()];
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        NSString *ns = [NSString stringWithUTF8String:name];
        NSString *lastComponent = [ns lastPathComponent];
        [result appendFormat:@"%@\n", lastComponent];
    }
    return result;
}

// ============ 原函数指针 ============
static void (*orig_StartCoolDown_v3)(void *thiz, float fCur, float fMax);
static void (*orig_EndCoolDown)(void *thiz);
static bool (*orig_IsInCoolDown)(void *thiz);

// ============ Hook实现 ============
static void new_StartCoolDown_v3(void *thiz, float fCur, float fMax) {
    g_hookHitCount_Start++;
    g_lastCurCD = fCur;
    g_lastMaxCD = fMax;

    if (g_bResetCDToZero) {
        fCur = 0.0f;
    }

    orig_StartCoolDown_v3(thiz, fCur, fMax);

    if (g_bResetCDToZero && thiz != NULL) {
        *(float *)((uintptr_t)thiz + OFFSET_fCurCoolDownTimeLeft) = 0.0f;
    }
}

static void new_EndCoolDown(void *thiz) {
    g_hookHitCount_End++;
    orig_EndCoolDown(thiz);
}

static bool new_IsInCoolDown(void *thiz) {
    bool ret = orig_IsInCoolDown(thiz);
    g_hookHitCount_IsIn++;

    if (g_bResetCDToZero) {
        return false;
    }
    return ret;
}

// ============ 真正安装Hook的函数 ============
static void TryInstallHooks(void) {
    if (g_bHooksInstalled) return;

    uintptr_t base = getModuleBaseAccurate(MODULE_NAME);
    if (base == 0) return;

    void *addr_v3 = (void *)(base + RVA_StartCoolDown_v3);
    MSHookFunction(addr_v3, (void *)new_StartCoolDown_v3, (void **)&orig_StartCoolDown_v3);

    void *addr_end = (void *)(base + RVA_EndCoolDown);
    MSHookFunction(addr_end, (void *)new_EndCoolDown, (void **)&orig_EndCoolDown);

    void *addr_isin = (void *)(base + RVA_IsInCoolDown);
    MSHookFunction(addr_isin, (void *)new_IsInCoolDown, (void **)&orig_IsInCoolDown);

    g_bHooksInstalled = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        ShowAlert(@"CDTweak 已加载", [NSString stringWithFormat:@"UnityFramework 基址: 0x%lx\n\n点左上角绿色按钮查看Hook状态", (unsigned long)base]);
        if (!g_statusButton) {
            g_statusButton = [[CDStatusButton alloc] init];
            // 注意：不调用 makeKeyAndVisible，避免抢占游戏主窗口的KeyWindow身份
        }
    });
}

// ============ dyld镜像加载回调：每次有新模块被加载都会触发 ============
static void OnImageAdded(const struct mach_header *mh, intptr_t vmaddr_slide) {
    TryInstallHooks();
}

// ============ 构造函数 ============
%ctor {
    TryInstallHooks();

    _dyld_register_func_for_add_image(OnImageAdded);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!g_bHooksInstalled) {
            NSString *allModules = ListAllModules();
            g_lastModuleListText = [allModules mutableCopy];
            ShowAlertWithCopy(@"CDTweak: 10秒内未找到 UnityFramework",
                               @"点下方按钮复制完整模块列表",
                               allModules);
        }
    });
}
