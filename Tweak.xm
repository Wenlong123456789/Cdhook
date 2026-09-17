#import <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import <string.h>
#import <stdint.h>

#define MODULE_NAME "UnityFramework"
#define RVA_TargetFunc 0x1AC9570

// ============================================================
// 目标函数开头特征码
// ============================================================

static const uint8_t kExpectedProlog[8] = {
    0xff, 0x43, 0x03, 0xd1,
    0xeb, 0x2b, 0x09, 0x6d
};

// ============================================================
// 全局状态
// ============================================================

static BOOL g_bModuleFound = NO;
static BOOL g_bPrologMatched = NO;
static BOOL g_bTargetReadable = NO;
static BOOL g_bHooksInstalled = NO;

static uintptr_t g_base = 0;
static uintptr_t g_target = 0;

static NSString *g_lastError = @"";


// ============================================================
// 获取 UnityFramework 基址
// ============================================================

static uintptr_t GetModuleBase(const char *moduleName)
{
    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {

        const char *name = _dyld_get_image_name(i);

        if (!name)
            continue;

        if (strstr(name, moduleName)) {

            const struct mach_header *header =
                _dyld_get_image_header(i);

            if (header) {
                return (uintptr_t)header;
            }
        }
    }

    return 0;
}


// ============================================================
// 检查目标地址和特征码
// ============================================================

static void CheckTarget(void)
{
    g_base = GetModuleBase(MODULE_NAME);

    if (g_base == 0) {

        g_bModuleFound = NO;
        g_bTargetReadable = NO;
        g_bPrologMatched = NO;

        g_lastError = @"没有找到 UnityFramework";

        NSLog(@"[CDTweak] UnityFramework 未找到");

        return;
    }

    g_bModuleFound = YES;

    g_target = g_base + RVA_TargetFunc;

    if (g_target < g_base) {

        g_bTargetReadable = NO;
        g_bPrologMatched = NO;

        g_lastError = @"目标地址计算溢出";

        NSLog(@"[CDTweak] 目标地址计算失败");

        return;
    }

    NSLog(@"[CDTweak] UnityFramework Base = 0x%llx",
          (unsigned long long)g_base);

    NSLog(@"[CDTweak] Target Address = 0x%llx",
          (unsigned long long)g_target);

    /*
     * 注意：
     *
     * 这里只读取目标地址上的 8 字节。
     *
     * 不执行 MSHookFunction
     * 不执行内存写入
     * 不修改目标函数
     */

    uint8_t current[8] = {0};

    /*
     * Objective-C 的 @try 无法捕获 EXC_BAD_ACCESS。
     * 因此这里仅在地址已经属于正常映像范围的情况下读取。
     *
     * 对于当前诊断用途，我们进一步通过 dladdr
     * 判断目标地址是否落在已加载映像中。
     */

    Dl_info info;

    memset(&info, 0, sizeof(info));

    if (dladdr((const void *)g_target, &info) == 0) {

        g_bTargetReadable = NO;
        g_bPrologMatched = NO;

        g_lastError =
            @"目标地址不属于当前已加载的 Mach-O 映像";

        NSLog(@"[CDTweak] dladdr failed");

        return;
    }

    g_bTargetReadable = YES;

    memcpy(current,
           (const void *)g_target,
           sizeof(current));

    NSLog(@"[CDTweak] Target bytes: "
          "%02X %02X %02X %02X %02X %02X %02X %02X",
          current[0],
          current[1],
          current[2],
          current[3],
          current[4],
          current[5],
          current[6],
          current[7]);

    if (memcmp(current,
               kExpectedProlog,
               sizeof(kExpectedProlog)) == 0) {

        g_bPrologMatched = YES;

        g_lastError =
            @"目标地址有效，特征码匹配";

        NSLog(@"[CDTweak] Prolog MATCH");

    } else {

        g_bPrologMatched = NO;

        char buffer[256];

        snprintf(
            buffer,
            sizeof(buffer),
            "特征码不匹配，实际数据: "
            "%02X %02X %02X %02X "
            "%02X %02X %02X %02X",

            current[0],
            current[1],
            current[2],
            current[3],
            current[4],
            current[5],
            current[6],
            current[7]
        );

        g_lastError =
            [NSString stringWithUTF8String:buffer];

        NSLog(@"[CDTweak] %@", g_lastError);
    }

    if (info.dli_fname) {

        NSLog(@"[CDTweak] Target image = %s",
              info.dli_fname);
    }
}


// ============================================================
// 悬浮按钮
// ============================================================

@interface SpeedButton : UIWindow
@end


@implementation SpeedButton

- (instancetype)init
{
    self = [super initWithFrame:
            CGRectMake(20.0, 120.0, 56.0, 56.0)];

    if (self) {

        self.backgroundColor = UIColor.clearColor;

        self.windowLevel = UIWindowLevelAlert + 1.0;

        self.hidden = NO;

        if (@available(iOS 13.0, *)) {

            for (UIWindowScene *scene
                 in UIApplication.sharedApplication.connectedScenes) {

                if (scene.activationState ==
                    UISceneActivationStateForegroundActive) {

                    self.windowScene = scene;

                    break;
                }
            }
        }

        UIButton *button =
            [UIButton buttonWithType:UIButtonTypeSystem];

        button.frame = self.bounds;

        button.backgroundColor =
            [UIColor colorWithWhite:0.10
                              alpha:0.92];

        button.layer.cornerRadius = 28.0;

        button.layer.masksToBounds = YES;

        [button setTitle:@"SPD"
                forState:UIControlStateNormal];

        [button setTitleColor:
                    UIColor.whiteColor
                forState:UIControlStateNormal];

        button.titleLabel.font =
            [UIFont boldSystemFontOfSize:14.0];

        [button addTarget:self
                   action:@selector(onTap)
         forControlEvents:UIControlEventTouchUpInside];

        [self addSubview:button];
    }

    return self;
}


// ============================================================
// 点击按钮
// ============================================================

- (void)onTap
{
    NSString *moduleStatus =
        g_bModuleFound ? @"是" : @"否";

    NSString *readStatus =
        g_bTargetReadable ? @"是" : @"否";

    NSString *prologStatus =
        g_bPrologMatched ? @"是" : @"否";

    NSString *hookStatus =
        g_bHooksInstalled ? @"是" : @"否";

    NSString *message =
        [NSString stringWithFormat:

         @"UnityFramework: %@\n"
          "目标地址可读取: %@\n"
          "特征码匹配: %@\n"
          "Hook: %@\n\n"
          "基址: 0x%llx\n"
          "目标地址: 0x%llx\n\n"
          "状态:\n%@",

         moduleStatus,
         readStatus,
         prologStatus,
         hookStatus,

         (unsigned long long)g_base,
         (unsigned long long)g_target,

         g_lastError ?: @"无"
        ];

    UIAlertController *alert =
        [UIAlertController
         alertControllerWithTitle:@"CDTweak 诊断"
         message:message
         preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction
         actionWithTitle:@"确定"
         style:UIAlertActionStyleCancel
         handler:nil]];


    UIViewController *root = nil;


    // ========================================================
    // iOS 13+
    // ========================================================

    if (@available(iOS 13.0, *)) {

        for (UIWindowScene *scene
             in UIApplication.sharedApplication.connectedScenes) {

            if (scene.activationState !=
                UISceneActivationStateForegroundActive) {

                continue;
            }

            for (UIWindow *window
                 in scene.windows) {

                if (window.isKeyWindow) {

                    root =
                        window.rootViewController;

                    break;
                }
            }

            if (root)
                break;
        }
    }


    // ========================================================
    // 兼容旧版 UIWindow
    // ========================================================

    if (!root) {

        for (UIWindow *window
             in UIApplication.sharedApplication.windows) {

            if (window.isKeyWindow) {

                root =
                    window.rootViewController;

                break;
            }
        }
    }


    if (!root)
        return;


    // ========================================================
    // 找到最上层控制器
    // ========================================================

    while (root.presentedViewController) {

        root =
            root.presentedViewController;
    }


    [root presentViewController:alert
                       animated:YES
                     completion:nil];
}

@end


static SpeedButton *g_button = nil;


// ============================================================
// 创建悬浮按钮
// ============================================================

static void CreateButton(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if (g_button)
            return;

        if (!UIApplication.sharedApplication)
            return;

        g_button =
            [[SpeedButton alloc] init];

    });
}


// ============================================================
// 延迟执行诊断
// ============================================================

static void RunDiagnostic(void)
{
    static BOOL scheduled = NO;

    if (scheduled)
        return;

    scheduled = YES;


    dispatch_async(dispatch_get_main_queue(), ^{

        /*
         * 等待 UIApplication / Scene / UnityFramework
         * 完成基本初始化。
         */

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(1.5 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{

                CheckTarget();

                CreateButton();


                NSLog(
                    @"[CDTweak] =========================="
                );

                NSLog(
                    @"[CDTweak] Module: %@",
                    g_bModuleFound ? @"FOUND" : @"NOT FOUND"
                );

                NSLog(
                    @"[CDTweak] Base: 0x%llx",
                    (unsigned long long)g_base
                );

                NSLog(
                    @"[CDTweak] Target: 0x%llx",
                    (unsigned long long)g_target
                );

                NSLog(
                    @"[CDTweak] Readable: %@",
                    g_bTargetReadable ? @"YES" : @"NO"
                );

                NSLog(
                    @"[CDTweak] Prolog: %@",
                    g_bPrologMatched ? @"MATCH" : @"MISMATCH"
                );

                NSLog(
                    @"[CDTweak] Hook: NOT INSTALLED"
                );

                NSLog(
                    @"[CDTweak] =========================="
                );
            }
        );
    });
}


// ============================================================
// DYLD Image 加载回调
// ============================================================

static void ImageAdded(
    const struct mach_header *mh,
    intptr_t slide)
{
    if (!mh)
        return;


    const char *name = NULL;

    uint32_t count =
        _dyld_image_count();


    for (uint32_t i = 0;
         i < count;
         i++) {

        const struct mach_header *header =
            _dyld_get_image_header(i);

        if (header == mh) {

            name =
                _dyld_get_image_name(i);

            break;
        }
    }


    if (!name)
        return;


    if (strstr(name, MODULE_NAME)) {

        NSLog(
            @"[CDTweak] UnityFramework loaded: %s",
            name
        );

        /*
         * 不在 dyld 回调内部安装 Hook。
         *
         * 只安排后续诊断。
         */

        RunDiagnostic();
    }


    (void)slide;
}


// ============================================================
// Tweak Constructor
// ============================================================

%ctor
{
    NSLog(
        @"[CDTweak] Constructor"
    );


    /*
     * 注册 UnityFramework 加载回调。
     */

    _dyld_register_func_for_add_image(
        ImageAdded
    );


    /*
     * 同时进行一次延迟检查。
     *
     * 处理一种情况：
     * UnityFramework 在注册 callback 之前
     * 已经加载完成。
     */

    RunDiagnostic();
}
