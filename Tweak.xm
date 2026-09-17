#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dispatch/dispatch.h>
#import <substrate.h>
#import <string.h>
#import <stdint.h>

#pragma mark - 配置

#define MODULE_NAME "UnityFramework"

// 你的目标 RVA
static const uintptr_t RVA_TargetFunc = 0x1AC9570;

// 目标函数预期特征
static const uint8_t kExpectedProlog[8] = {
    0xff, 0x43, 0x03, 0xd1,
    0xeb, 0x2b, 0x09, 0x6d
};

#pragma mark - 全局状态

static BOOL g_bModuleFound = NO;
static BOOL g_bPrologMatched = NO;
static BOOL g_bTargetReadable = NO;
static BOOL g_bHooksInstalled = NO;

static uintptr_t g_base = 0;
static uintptr_t g_target = 0;

static NSString *g_lastError = @"暂无";

#pragma mark - SPD Window

@interface SPDViewController : UIViewController
@end

@implementation SPDViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.clearColor;

    UIButton *button =
        [UIButton buttonWithType:UIButtonTypeSystem];

    button.frame =
        CGRectMake(10, 10, 60, 60);

    button.backgroundColor =
        [UIColor colorWithRed:0.85
                        green:0.20
                         blue:0.20
                        alpha:0.95];

    button.layer.cornerRadius = 30.0;
    button.clipsToBounds = YES;

    [button setTitle:@"SPD"
            forState:UIControlStateNormal];

    [button setTitleColor:UIColor.whiteColor
                  forState:UIControlStateNormal];

    button.titleLabel.font =
        [UIFont boldSystemFontOfSize:14.0];

    [button addTarget:self
               action:@selector(spdButtonClicked:)
     forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:button];
}

- (void)spdButtonClicked:(UIButton *)sender
{
    NSString *message =
        [NSString stringWithFormat:
            @"模块找到：%@\n"
             "目标地址可读取：%@\n"
             "特征码匹配：%@\n"
             "Hook：%@\n\n"
             "UnityFramework 基址：0x%llx\n"
             "目标地址：0x%llx\n\n"
             "错误：%@",

            g_bModuleFound ? @"是" : @"否",

            g_bTargetReadable ? @"是" : @"否",

            g_bPrologMatched ? @"是" : @"否",

            g_bHooksInstalled ? @"已安装" : @"未安装",

            (unsigned long long)g_base,

            (unsigned long long)g_target,

            g_lastError
        ];

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:@"CDTweak 状态"
            message:message
            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"确定"
                      style:UIAlertActionStyleDefault
                    handler:nil]];

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

@end


@interface SPDWindow : UIWindow
@end

@implementation SPDWindow
@end


static SPDWindow *g_spdWindow = nil;

#pragma mark - 获取当前 WindowScene

static UIWindowScene *GetActiveWindowScene(void)
{
    if (@available(iOS 13.0, *)) {

        // 优先获取正在前台活动的 Scene
        for (UIScene *scene
             in UIApplication.sharedApplication.connectedScenes) {

            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            if (windowScene.activationState ==
                UISceneActivationStateForegroundActive) {

                return windowScene;
            }
        }

        // 如果没有 Active，则尝试 Inactive
        for (UIScene *scene
             in UIApplication.sharedApplication.connectedScenes) {

            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            if (windowScene.activationState ==
                UISceneActivationStateForegroundInactive) {

                return windowScene;
            }
        }
    }

    return nil;
}

#pragma mark - 创建 SPD Window

static void CreateSPDWindow(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        // 已经创建过就不重复创建
        if (g_spdWindow != nil) {

            g_spdWindow.hidden = NO;

            return;
        }

        UIWindowScene *scene =
            GetActiveWindowScene();

        if (@available(iOS 13.0, *)) {

            if (scene == nil) {

                NSLog(@"[CDTweak] 找不到当前 UIWindowScene");

                g_lastError =
                    @"找不到当前 UIWindowScene";

                return;
            }

            g_spdWindow =
                [[SPDWindow alloc]
                    initWithWindowScene:scene];

        } else {

            g_spdWindow =
                [[SPDWindow alloc]
                    initWithFrame:
                        CGRectMake(
                            20,
                            120,
                            80,
                            80)];
        }

        // 悬浮按钮窗口位置
        g_spdWindow.frame =
            CGRectMake(
                20,
                120,
                80,
                80);

        g_spdWindow.backgroundColor =
            UIColor.clearColor;

        // 设置窗口层级
        g_spdWindow.windowLevel =
            UIWindowLevelAlert + 1.0;

        // 创建控制器
        SPDViewController *vc =
            [[SPDViewController alloc] init];

        g_spdWindow.rootViewController = vc;

        // 显示
        g_spdWindow.hidden = NO;

        [g_spdWindow makeKeyAndVisible];

        NSLog(@"[CDTweak] SPD Window 创建成功");

        // 避免长期抢宿主 App 的 KeyWindow
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(0.1 * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{

                if (g_spdWindow != nil) {
                    [g_spdWindow resignKeyWindow];
                }
            });
    });
}

#pragma mark - 获取 UnityFramework 基址

static uintptr_t GetModuleBase(const char *moduleName)
{
    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {

        const char *imageName =
            _dyld_get_image_name(i);

        if (imageName == NULL) {
            continue;
        }

        if (strstr(imageName, moduleName) != NULL) {

            const struct mach_header *header =
                _dyld_get_image_header(i);

            if (header != NULL) {

                return (uintptr_t)header;
            }
        }
    }

    return 0;
}

#pragma mark - 查找模块

static void CheckUnityFramework(void)
{
    g_base = GetModuleBase(MODULE_NAME);

    if (g_base == 0) {

        g_bModuleFound = NO;
        g_bPrologMatched = NO;
        g_bTargetReadable = NO;
        g_target = 0;

        g_lastError =
            @"没有找到 UnityFramework";

        NSLog(@"[CDTweak] UnityFramework 未找到");

        return;
    }

    g_bModuleFound = YES;

    NSLog(
        @"[CDTweak] UnityFramework 基址: 0x%llx",
        (unsigned long long)g_base
    );

    g_target =
        g_base + RVA_TargetFunc;

    NSLog(
        @"[CDTweak] 目标地址: 0x%llx",
        (unsigned long long)g_target
    );

    /*
     * 这里只进行基础 Mach-O 地址范围检查。
     * 不执行 Hook，也不修改目标地址。
     */

    BOOL addressInImage = NO;

    uint32_t count =
        _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {

        const struct mach_header *header =
            _dyld_get_image_header(i);

        if (header == NULL) {
            continue;
        }

        uintptr_t imageBase =
            (uintptr_t)header;

        if (imageBase != g_base) {
            continue;
        }

        intptr_t slide =
            _dyld_get_image_vmaddr_slide(i);

        /*
         * 这里只确认目标地址位于
         * UnityFramework 映像之后。
         */
        uintptr_t runtimeBase =
            imageBase + slide;

        if (g_target >= runtimeBase) {
            addressInImage = YES;
        }

        break;
    }

    if (!addressInImage) {

        g_bTargetReadable = NO;
        g_bPrologMatched = NO;

        g_lastError =
            @"目标 RVA 不在当前映像范围";

        NSLog(
            @"[CDTweak] 目标地址范围检查失败"
        );

        return;
    }

    /*
     * 注意：
     * 这里只在地址通过基础检查后读取 8 字节。
     */

    uint8_t bytes[8] = {0};

    memcpy(
        bytes,
        (const void *)g_target,
        sizeof(bytes)
    );

    g_bTargetReadable = YES;

    NSLog(
        @"[CDTweak] 目标前8字节: "
        "%02x %02x %02x %02x "
        "%02x %02x %02x %02x",

        bytes[0],
        bytes[1],
        bytes[2],
        bytes[3],
        bytes[4],
        bytes[5],
        bytes[6],
        bytes[7]
    );

    if (memcmp(
            bytes,
            kExpectedProlog,
            sizeof(kExpectedProlog)
        ) == 0) {

        g_bPrologMatched = YES;

        g_lastError =
            @"特征码匹配";

        NSLog(
            @"[CDTweak] 特征码匹配"
        );

    } else {

        g_bPrologMatched = NO;

        g_lastError =
            @"特征码不匹配，可能是版本/RVA 不对应";

        NSLog(
            @"[CDTweak] 特征码不匹配"
        );
    }
}

#pragma mark - 显示诊断结果

static void ShowDiagnosticAlert(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if (g_spdWindow == nil) {
            return;
        }

        UIViewController *vc =
            g_spdWindow.rootViewController;

        if (vc == nil) {
            return;
        }

        NSString *message =
            [NSString stringWithFormat:
                @"UnityFramework：%@\n"
                 "目标地址：0x%llx\n"
                 "地址检查：%@\n"
                 "特征码：%@\n"
                 "Hook：%@\n\n"
                 "%@",

                g_bModuleFound ? @"已找到" : @"未找到",

                (unsigned long long)g_target,

                g_bTargetReadable ? @"通过" : @"失败",

                g_bPrologMatched ? @"匹配" : @"不匹配",

                g_bHooksInstalled ? @"已安装" : @"未安装",

                g_lastError
            ];

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:@"CDTweak 诊断"
                message:message
                preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"确定"
                          style:UIAlertActionStyleDefault
                        handler:nil]];

        [vc presentViewController:alert
                          animated:YES
                        completion:nil];
    });
}

#pragma mark - 初始化

%ctor
{
    NSLog(@"[CDTweak] Tweak loaded");

    /*
     * 等待 App / Unity / Scene 初始化完成。
     */
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(3.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{

            NSLog(
                @"[CDTweak] 开始检查 UnityFramework"
            );

            CheckUnityFramework();

            /*
             * 创建 SPD 悬浮按钮。
             */
            CreateSPDWindow();

            /*
             * 再延迟一点显示诊断结果。
             */
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)(1.0 * NSEC_PER_SEC)),
                dispatch_get_main_queue(),
                ^{

                    ShowDiagnosticAlert();
                });
        }
    );
}
