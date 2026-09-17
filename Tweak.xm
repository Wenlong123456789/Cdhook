#import <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#import <dispatch/dispatch.h>
#import <string.h>
#import <stdint.h>

#define MODULE_NAME "UnityFramework"
#define RVA_TargetFunc 0x1AC9570

// ============================================================
// 目标函数特征码
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
static BOOL g_bExecutable = NO;

static uintptr_t g_base = 0;
static uintptr_t g_target = 0;

static NSString *g_lastError = @"";

// 注意：诊断版本故意不安装 Hook
static BOOL g_bHooksInstalled = NO;


// ============================================================
// 查找 UnityFramework
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
// 判断地址是否属于当前进程的 Mach-O 映像
// ============================================================

static BOOL IsAddressInsideImage(uintptr_t address)
{
    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {

        const struct mach_header *header =
            _dyld_get_image_header(i);

        if (!header)
            continue;

        uintptr_t base = (uintptr_t)header;

        intptr_t slide =
            _dyld_get_image_vmaddr_slide(i);

        uintptr_t vmBase = base;

        // 这里主要用于避免明显非法地址。
        // 不直接对任意地址进行写操作。
        if (address >= vmBase &&
            address < vmBase + 0x100000000ULL) {

            return YES;
        }

        (void)slide;
    }

    return NO;
}


// ============================================================
// 检查目标地址
// ============================================================

static void CheckTarget(void)
{
    g_base = GetModuleBase(MODULE_NAME);

    if (g_base == 0) {

        g_bModuleFound = NO;
        g_lastError = @"没有找到 UnityFramework";

        return;
    }

    g_bModuleFound = YES;

    g_target = g_base + RVA_TargetFunc;

    if (g_target < g_base) {

        g_lastError = @"目标地址计算溢出";

        return;
    }

    /*
     * 这里只读取 8 字节。
     *
     * 不执行：
     *
     * MSHookFunction()
     * mach_vm_write()
     * 内存修改
     *
     * 这样可以先确定闪退到底是不是 Hook 引起。
     */

    @try {

        uint8_t current[8] = {0};

        memcpy(current,
               (const void *)g_target,
               sizeof(current));

        g_bTargetReadable = YES;

        if (memcmp(current,
                   kExpectedProlog,
                   sizeof(kExpectedProlog)) == 0) {

            g_bPrologMatched = YES;
            g_lastError = @"目标地址和特征码匹配";

        } else {

            g_bPrologMatched = NO;

            char buffer[256];

            snprintf(buffer,
                     sizeof(buffer),
                     "特征码不匹配: %02X %02X %02X %02X "
                     "%02X %02X %02X %02X",
                     current[0],
                     current[1],
                     current[2],
                     current[3],
                     current[4],
                     current[5],
                     current[6],
                     current[7]);

            g_lastError =
                [NSString stringWithUTF8String:buffer];
        }

    } @catch (NSException *exception) {

        g_bTargetReadable = NO;

        g_lastError =
            [NSString stringWithFormat:
             @"读取目标地址异常: %@",
             exception.reason ?: @"未知异常"];
    }
}


// ============================================================
// 状态窗口
// ============================================================

@interface SpeedButton : UIWindow
@end

@implementation SpeedButton

- (instancetype)init
{
    self = [super initWithFrame:CGRectMake(20, 120, 56, 56)];

    if (self) {

        self.backgroundColor = UIColor.clearColor;

        self.windowLevel = UIWindowLevelAlert + 1;

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
            [UIColor colorWithWhite:0.1 alpha:0.92];

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


- (void)onTap
{
    NSString *module =
        g_bModuleFound ? @"是" : @"否";

    NSString *prolog =
        g_bPrologMatched ? @"是" : @"否";

    NSString *readable =
        g_bTargetReadable ? @"是" : @"否";

    NSString *installed =
        g_bHooksInstalled ? @"是" : @"否";

    NSString *message =
        [NSString stringWithFormat:

         @"UnityFramework: %@\n"
          "目标可读取: %@\n"
          "特征码匹配: %@\n"
          "Hook: %@\n\n"
          "基址: 0x%llx\n"
          "目标: 0x%llx\n\n"
          "状态:\n%@",

         module,
         readable,
         prolog,
         installed,

         (unsigned long long)g_base,
         (unsigned long long)g_target,

         g_lastError ?: @"无"];

    UIAlertController *alert =
        [UIAlertController
         alertControllerWithTitle:@"SpeedTweak 诊断"
         message:message
         preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction
         actionWithTitle:@"确定"
         style:UIAlertActionStyleCancel
         handler:nil]];

    UIViewController *root = nil;

    if (@available(iOS 13.0, *)) {

        for (UIWindowScene *scene
             in UIApplication.sharedApplication.connectedScenes) {

            if (scene.activationState ==
                UISceneActivationStateForegroundActive) {

                for (UIWindow *window in scene.windows) {

                    if (window.isKeyWindow) {
                        root = window.rootViewController;
                        break;
                    }
                }

                if (root)
                    break;
            }
        }
    }

    if (!root) {

        for (UIWindow *window
             in UIApplication.sharedApplication.windows) {

            if (window.isKeyWindow) {

                root = window.rootViewController;
                break;
            }
        }
    }

    if (!root)
        return;

    while (root.presentedViewController) {
        root = root.presentedViewController;
    }

    [root presentViewController:alert
                       animated:YES
                     completion:nil];
}

@end


static SpeedButton *g_button = nil;


// ============================================================
// 创建 UI
// ============================================================

static void CreateButton(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if (g_button)
            return;

        if (!UIApplication.sharedApplication)
            return;

        g_button = [[SpeedButton alloc] init];
    });
}


// ============================================================
// UnityFramework 加载后的处理
// ============================================================

static void InstallDiagnostic(void)
{
    static BOOL processing = NO;

    if (processing)
        return;

    processing = YES;

    /*
     * 延迟到主线程启动后再检查。
     *
     * 避免在 dylib constructor 阶段：
     *
     * UIApplication
     * Scene
     * UnityFramework
     *
     * 同时初始化。
     */

    dispatch_async(dispatch_get_main_queue(), ^{

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(1.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{

                CheckTarget();

                CreateButton();

                NSString *message =
                    [NSString stringWithFormat:

                     @"UnityFramework: %@\n"
                      "目标地址可读取: %@\n"
                      "特征码匹配: %@\n\n"
                      "基址: 0x%llx\n"
                      "目标地址: 0x%llx\n\n"
                      "%@",

                     g_bModuleFound ? @"已找到" : @"未找到",

                     g_bTargetReadable ? @"是" : @"否",

                     g_bPrologMatched ? @"是" : @"否",

                     (unsigned long long)g_base,

                     (unsigned long long)g_target,

                     g_lastError ?: @""];

                /*
                 * 这里暂时不自动弹窗。
                 *
                 * 防止测试时弹窗机制本身影响启动。
                 */

                NSLog(
                    @"[SpeedTweak] %@",
                    message);
            });
    });
}


// ============================================================
// Image 加载回调
// ============================================================

static void ImageAdded(
    const struct mach_header *mh,
    intptr_t slide)
{
    if (!mh)
        return;

    const char *name = NULL;

    /*
     * 这里只通过 dyld image 列表判断，
     * 不在 dyld callback 中直接安装 Hook。
     */

    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {

        const struct mach_header *header =
            _dyld_get_image_header(i);

        if (header != mh)
            continue;

        name = _dyld_get_image_name(i);

        break;
    }

    if (!name)
        return;

    if (strstr(name, MODULE_NAME)) {

        /*
         * UnityFramework 已经出现。
         *
         * 不直接 Hook。
         * 延迟到正常 UI 生命周期。
         */

        InstallDiagnostic();
    }

    (void)slide;
}


// ============================================================
// Constructor
// ============================================================

%ctor
{
    /*
     * 先注册 image callback。
     */

    _dyld_register_func_for_add_image(ImageAdded);

    /*
     * 如果 UnityFramework 已经加载，
     * 也进行一次延迟检查。
     */

    InstallDiagnostic();
}
