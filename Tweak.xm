#import <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <string.h>

#define MODULE_NAME "UnityFramework"
#define RVA_UpdateCD  0x21EC7A4

static BOOL g_bNoCD = YES;
static BOOL g_bHooksInstalled = NO;
static NSInteger g_hitCount = 0;
static uintptr_t g_base = 0;

// ============ 简单状态按钮 ============
@interface CDButton : UIWindow
@end
@implementation CDButton
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
        btn.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.95 alpha:0.9];
        btn.layer.cornerRadius = 25;
        [btn setTitle:@"CD" forState:UIControlStateNormal];
        [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [btn addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];
    }
    return self;
}
- (void)onTap {
    NSString *msg = [NSString stringWithFormat:
        @"Hook: %@\n命中: %ld\n无CD: %@\n基址: 0x%lx",
        g_bHooksInstalled ? @"是" : @"否",
        (long)g_hitCount,
        g_bNoCD ? @"开" : @"关",
        (unsigned long)g_base];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CDTweak"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:g_bNoCD ? @"关闭无CD" : @"开启无CD"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a) {
        g_bNoCD = !g_bNoCD;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];

    UIWindow *key = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow) { key = w; break; }
    }
    [key.rootViewController presentViewController:alert animated:YES completion:nil];
}
@end

static CDButton *g_btn = nil;

// ============ Hook（带 MethodInfo*） ============
static void (*orig_UpdateCD)(void *thiz, void *method);

static void new_UpdateCD(void *thiz, void *method) {
    g_hitCount++;

    if (g_bNoCD && thiz) {
        int32_t *p = (int32_t *)((uintptr_t)thiz + 0x60);
        if (*p > 0) {
            *p = 0;
        }
    }

    orig_UpdateCD(thiz, method);
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
    });
}

static void OnImageAdded(const struct mach_header *mh, intptr_t slide) {
    TryInstall();
}

%ctor {
    TryInstall();
    _dyld_register_func_for_add_image(OnImageAdded);
}
