#include "CMultitouch.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdbool.h>

static void *lib;
static CFArrayRef (*p_MTDeviceCreateList)(void);
static void (*p_MTRegisterContactFrameCallback)(MTDeviceRef, MTContactCallback);
static void (*p_MTUnregisterContactFrameCallback)(MTDeviceRef, MTContactCallback);
static void (*p_MTDeviceStart)(MTDeviceRef, int);
static void (*p_MTDeviceStop)(MTDeviceRef);
static bool (*p_MTDeviceIsBuiltIn)(MTDeviceRef);

int mt_load(char *err, size_t errlen) {
    if (lib) return 0;
    lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (!lib) { snprintf(err, errlen, "dlopen failed: %s", dlerror()); return -1; }
#define LOAD(name) p_##name = dlsym(lib, #name); \
    if (!p_##name) { snprintf(err, errlen, "missing symbol %s", #name); return -1; }
    LOAD(MTDeviceCreateList)
    LOAD(MTRegisterContactFrameCallback)
    LOAD(MTUnregisterContactFrameCallback)
    LOAD(MTDeviceStart)
    LOAD(MTDeviceStop)
#undef LOAD
    p_MTDeviceIsBuiltIn = dlsym(lib, "MTDeviceIsBuiltIn");   // optional
    return 0;
}

CFArrayRef mt_device_list(void) { return p_MTDeviceCreateList(); }
void mt_register(MTDeviceRef dev, MTContactCallback cb)   { p_MTRegisterContactFrameCallback(dev, cb); }
void mt_unregister(MTDeviceRef dev, MTContactCallback cb) { p_MTUnregisterContactFrameCallback(dev, cb); }
void mt_start(MTDeviceRef dev) { p_MTDeviceStart(dev, 0); }
void mt_stop(MTDeviceRef dev)  { p_MTDeviceStop(dev); }
int  mt_is_builtin(MTDeviceRef dev) { return p_MTDeviceIsBuiltIn ? (p_MTDeviceIsBuiltIn(dev) ? 1 : 0) : -1; }
