#import <substrate.h>
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <string.h>

#define MODULE_NAME "UnityFramework"

static BOOL g_installed = NO;

static uintptr_t getModuleBase(const char *name) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (strstr(_dyld_get_image_name(i), name)) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

static void TryInstall() {
    if (g_installed) return;
    uintptr_t base = getModuleBase(MODULE_NAME);
    if (base == 0) return;
    g_installed = YES;
    NSLog(@"[CDTweak] 最小模式已加载，基址: 0x%lx", base);
}

static void OnImageAdded(const struct mach_header *mh, intptr_t slide) {
    TryInstall();
}

%ctor {
    TryInstall();
    _dyld_register_func_for_add_image(OnImageAdded);
}
