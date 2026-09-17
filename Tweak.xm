#import <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
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
// 获取模块基址
// ============================================================

static uintptr_t GetModuleBase(const char *moduleName)
{
    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {

        const char *name = _dyld_get_image_name(i);

        if (name == NULL)
            continue;

        if (strstr(name, moduleName) == NULL)
            continue;

        const struct mach_header *header =
            _dyld_get_image_header(i);

        if (header == NULL)
            continue;

        return (uintptr_t)header;
    }

    return 0;
}


// ============================================================
// 检查目标地址
// ============================================================

static void CheckTarget(void)
{
    g_base = GetModuleBase(MODULE_NAME);

    if (g_base == 0) {

        g_bModuleFound = NO;
        g_bTargetReadable = NO;
        g_bPrologMatched = NO;

        g_lastError =
            @"没有找到 UnityFramework";

        NSLog(@"[CDTweak] UnityFramework 未找到");

        return;
    }

    g_bModuleFound = YES;

    // ========================================================
    // 计算目标地址
    // ========================================================

    g_target =
        g_base + (uintptr_t)RVA_TargetFunc;

    if (g_target < g_base) {

        g_bTargetReadable = NO;
        g_bPrologMatched = NO;

        g_lastError =
            @"目标地址计算溢出";

        NSLog(
            @"[CDTweak] 目标地址计算失败"
        );

        return;
    }

    NSLog(
        @"[CDTweak] UnityFramework Base = 0x%llx",
        (unsigned long long)g_base
    );

    NSLog(
        @"[CDTweak] Target Address = 0x%llx",
        (unsigned long long)g_target
    );


    // ========================================================
    // 使用 dladdr 检查地址是否属于已加载映像
    // ========================================================

    struct Dl_info info;

    memset(
        &info,
        0,
        sizeof(info)
    );

    int result =
        dladdr(
            (const void *)g_target,
            &info
        );

    if (result == 0) {

        g_bTargetReadable = NO;
        g_bPrologMatched = NO;

        g_lastError =
            @"目标地址不属于当前已加载的 Mach-O 映像";

        NSLog(
            @"[CDTweak] dladdr failed"
        );

        return;
    }


    g_bTargetReadable = YES;


    // ========================================================
    // 读取目标地址前 8 字节
    // ========================================================

    uint8_t current[8] = {0};

    memcpy(
        current,
        (const void *)g_target,
        sizeof(current)
    );


    NSLog(
        @"[CDTweak] Target bytes: "
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


    // ========================================================
    // 比较特征码
    // ========================================================

    if (memcmp(
            current,
            kExpectedProlog,
            sizeof(kExpectedProlog)
        ) == 0) {

        g_bPrologMatched = YES;

        g_lastError =
            @"目标地址有效，特征码匹配";

        NSLog(
            @"[CDTweak] Prolog MATCH"
        );

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

        NSLog(
            @"[CDTweak] %s",
            buffer
        );
    }


    // ========================================================
    // 输出目标地址所属映像
    // ========================================================

    if (info.dli_fname != NULL) {

        NSLog(
            @"[CDTweak] Target image = %s",
            info.dli_fname
        );
    }

    if (info.dli_sname != NULL) {

        NSLog(
            @"[CDTweak] Target symbol = %s",
            info.dli_sname
        );
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
    self =
        [super initWithFrame:
            CGRectMake(
                20.0,
                120.0,
                56.0,
                56.0
            )];

    if (self) {

        // ====================================================
        // UIWindow
        // ====================================================

        self.backgroundColor =
            UIColor.clearColor;

        self.windowLevel =
            UIWindowLevelAlert + 1.0;

        self.hidden = NO;


        // ====================================================
        // iOS 13+ Scene
        // ====================================================

        if (@available(iOS 13.0, *)) {

            for (UIWindowScene *scene
                 in UIApplication.sharedApplication.connectedScenes) {

                if (scene.activationState ==
                    UISceneActivationStateForegroundActive) {

                    self.windowScene =
                        scene;

                    break;
                }
            }
        }


        // ====================================================
        // 创建按钮
        // ====================================================

        UIButton *button =
            [UIButton buttonWithType:
                UIButtonTypeSystem];

        button.frame =
            self.bounds;

        button.backgroundColor =
            [UIColor colorWithWhite:0.10
                              alpha:0.92];

        button.layer.cornerRadius =
            28.0;

        button.layer.masksToBounds =
            YES;

        [button setTitle:@"SPD"
                forState:
                    UIControlStateNormal];

        [button setTitleColor:
                    UIColor.whiteColor
                forState:
                    UIControlStateNormal];

        button.titleLabel.font =
            [UIFont boldSystemFontOfSize:14.0];

        [button addTarget:self
                   action:@selector(onTap)
         forControlEvents:
             UIControlEventTouchUpInside];

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
        g_bModuleFound
            ? @"是"
            : @"否";

    NSString *readStatus =
        g_bTargetReadable
            ? @"是"
            : @"否";

    NSString *prologStatus =
        g_bPrologMatched
            ? @"是"
            : @"否";

    NSString *hookStatus =
        g_bHooksInstalled
            ? @"是"
            : @"否";


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


    // ========================================================
    // 创建 Alert
    // ========================================================

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:
                @"CDTweak 诊断"

            message:
                message

            preferredStyle:
                UIAlertControllerStyleAlert];


    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"确定"
            style:
                UIAlertActionStyleCancel
            handler:nil]];


    // ========================================================
    // 查找当前 UIWindow
    // ========================================================

    UIViewController *root =
        nil;


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
    // 获取最上层控制器
    // ========================================================

    while (root.presentedViewController) {

        root =
            root.presentedViewController;
    }


    // ========================================================
    // 显示
    // ========================================================

    [root presentViewController:
        alert

        animated:YES

        completion:nil];
}

@end


// ============================================================
// 全局悬浮按钮
// ============================================================

static SpeedButton *g_button = nil;


// ============================================================
// 创建悬浮按钮
// ============================================================

static void CreateButton(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (g_button)
                return;

            if (!UIApplication.sharedApplication)
                return;


            g_button =
                [[SpeedButton alloc] init];

        }
    );
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


    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            /*
             * 等待 App / Scene / UnityFramework
             * 完成基本初始化。
             */

            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)(
                        1.5 *
                        NSEC_PER_SEC
                    )
                ),

                dispatch_get_main_queue(),

                ^{

                    // ========================================
                    // 检查模块和目标地址
                    // ========================================

                    CheckTarget();


                    // ========================================
                    // 创建悬浮按钮
                    // ========================================

                    CreateButton();


                    // ========================================
                    // 输出日志
                    // ========================================

                    NSLog(
                        @"[CDTweak] "
                        @"=========================="
                    );


                    NSLog(
                        @"[CDTweak] Module: %@",
                        g_bModuleFound
                            ? @"FOUND"
                            : @"NOT FOUND"
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
                        g_bTargetReadable
                            ? @"YES"
                            : @"NO"
                    );


                    NSLog(
                        @"[CDTweak] Prolog: %@",
                        g_bPrologMatched
                            ? @"MATCH"
                            : @"MISMATCH"
                    );


                    NSLog(
                        @"[CDTweak] Hook: NOT INSTALLED"
                    );


                    NSLog(
                        @"[CDTweak] Error: %@",
                        g_lastError ?: @"NONE"
                    );


                    NSLog(
                        @"[CDTweak] "
                        @"=========================="
                    );
                }
            );
        }
    );
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


    const char *name =
        NULL;


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


    if (strstr(
            name,
            MODULE_NAME
        ) != NULL) {

        NSLog(
            @"[CDTweak] "
            @"UnityFramework loaded: %s",
            name
        );


        /*
         * 不在 dyld callback 内安装 Hook。
         *
         * 这里只进行延迟诊断。
         */

        RunDiagnostic();
    }


    (void)slide;
}


// ============================================================
// Constructor
// ============================================================

%ctor
{
    NSLog(
        @"[CDTweak] Constructor"
    );


    // ========================================================
    // 注册 Image 加载回调
    // ========================================================

    _dyld_register_func_for_add_image(
        ImageAdded
    );


    // ========================================================
    // 延迟执行一次诊断
    // ========================================================

    RunDiagnostic();
}
