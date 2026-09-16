#import <substrate.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

#define MODULE_NAME "UnityFramework"

// 你抓到的真实 Update 函数入口
#define RVA_UpdateCD  0x21EC7A4

// 该函数里 CD 剩余时间的偏移
#define OFFSET_CD     0x60

static BOOL g_bNoCD = YES;   // 默认开启无CD
static BOOL g_bHooksInstalled = NO;
static NSInteger g_hitCount = 0;

// 原函数
static void (*orig_UpdateCD)(void *thiz, void *method);

// Hook 实现
static void new_UpdateCD(void *thiz, void *method) {
    g_hitCount++;

    if (g_bNoCD && thiz) {
        // 强制把 CD 剩余时间写成 0
        *(int32_t *)((uintptr_t)thiz + OFFSET_CD) = 0;
    }

    // 继续执行原函数（可选，如果想完全跳过可以注释掉）
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

static void TryInstallHooks() {
    if (g_bHooksInstalled) return;

    uintptr_t base = getModuleBase(MODULE_NAME);
    if (base == 0) return;

    void *addr = (void *)(base + RVA_UpdateCD);
    MSHookFunction(addr, (void *)new_UpdateCD, (void **)&orig_UpdateCD);

    g_bHooksInstalled = YES;
    NSLog(@"[CDTweak] Hook 成功，基址: 0x%lx, RVA: 0x%lx", base, (unsigned long)RVA_UpdateCD);
}

static void OnImageAdded(const struct mach_header *mh, intptr_t slide) {
    TryInstallHooks();
}

%ctor {
    TryInstallHooks();
    _dyld_register_func_for_add_image(OnImageAdded);
}
