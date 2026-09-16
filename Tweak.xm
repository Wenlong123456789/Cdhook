#import <substrate.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

#define MODULE_NAME "UnityFramework"
#define RVA_UpdateCD  0x21EC7A4
#define OFFSET_CD     0x60

static BOOL g_bNoCD = YES;
static BOOL g_bHooksInstalled = NO;
static NSInteger g_hitCount = 0;
static uintptr_t g_base = 0;

// ============ 弹窗容器（触摸穿透） ============
@interface CDAlertHostWindow : UIWindow
@end
@implementation CDAlertHostWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

static CDAlertHostWindow *g_alertWindow = nil;
static UIViewController *g_alertVC = nil;

static UIViewController *GetAlertVC() {
    if (g_alertWindow) return g_alertVC;

    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                g_alertWindow = [[CDAlertHostWindow alloc] initWithWindowScene:scene];
                break;
            }
        }
    }
    if (!g_alertWindow) {
        g_alertWindow = [[CDAlertHostWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    }

    g_alertVC = [UIViewController new];
    g_alertVC.view.backgroundColor = UIColor.clearColor;
    g_alertVC.view.userInteractionEnabled = NO;

    g_alertWindow.rootViewController = g_alertVC;
    g_alertWindow.windowLevel = UIWindowLevelAlert + 1;
    g_alertWindow.backgroundColor = UIColor.clearColor;
    g_alertWindow.hidden = NO;
    return g_alertVC;
}

static void ShowStatus() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = GetAlertVC();
        if (!vc) return;
        vc.view.userInteractionEnabled = YES;

        if (vc.presentedViewController) {
            [vc dismissViewControllerAnimated:NO completion:nil];
        }

        NSString *msg = [NSString stringWithFormat:
            @"Hook状态: %@\n"
            @"命中次数: %ld\n"
            @"无CD开关: %@\n"
            @"基址: 0x%lx\n"
            @"RVA: 0x%X",
            g_bHooksInstalled ? @"已安装" : @"未安装",
            (long)g_hitCount,
            g_bNoCD ? @"开启" : @"关闭",
            (unsigned long)g_base,
            RVA_UpdateCD];

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CDTweak 状态"
                                                                       message:msg
                                                                preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:g_bNoCD ? @"关闭无CD" : @"开启无CD"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *a) {
            g_bNoCD = !g_bNoCD;
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
            vc.view.userInteractionEnabled = NO;
        }]];

        [vc presentViewController:alert animated:YES completion:nil];
    });
}

// ============ 悬浮按钮 ============
@interface CDButton : UIWindow
@end
@implementation CDButton
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 56, 56)];
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
        btn.frame = CGRectMake(0, 0, 56, 56);
        btn.backgroundColor = [UIColor colorWithRed:0.1 green:0.55 blue:0.9 alpha:0.9];
        btn.layer.cornerRadius = 28;
        [btn setTitle:@"CD" forState:UIControlStateNormal];
        [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [btn addTarget:self action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [btn addGestureRecognizer:pan];
        [self addSubview:btn];
    }
    return self;
}
- (void)drag:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [p setTranslation:CGPointZero inView:self];
}
- (void)tap {
    ShowStatus();
}
@end

static CDButton *g_btn = nil;

// ============ Hook ============
static void (*orig_UpdateCD)(void *thiz);

static void new_UpdateCD(void *thiz) {
    g_hitCount++;

    if (g_bNoCD && thiz) {
        int32_t *p = (int32_t *)((uintptr_t)thiz + OFFSET_CD);
        if (*p > 0) *p = 0;
    }
    orig_UpdateCD(thiz);
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

    void *addr = (void *)(g_base + RVA_UpdateCD);
    MSHookFunction(addr, (void *)new_UpdateCD, (void **)&orig_UpdateCD);

    g_bHooksInstalled = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_btn) g_btn = [CDButton new];
        ShowStatus();
    });
}

static void OnImageAdded(const struct mach_header *mh, intptr_t slide) {
    TryInstall();
}

%ctor {
    TryInstall();
    _dyld_register_func_for_add_image(OnImageAdded);
}
