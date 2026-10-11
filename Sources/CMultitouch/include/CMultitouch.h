// Thin entry point to Apple's private MultitouchSupport.framework.
// Loaded at runtime with dlopen; only the functions we need are resolved.
// The struct layout is the one MiddleClick, Kivy and others have relied on for years.
#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stddef.h>

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTReadout;

// One finger in one frame. 96 bytes.
typedef struct {
    int32_t  frame;
    double   timestamp;
    int32_t  identifier;   // stays the same while the finger is down
    int32_t  state;        // 1 approaching 2 hovering 3 making touch 4 touching 5 breaking touch 6 lingering 7 out of range
    int32_t  fingerId;
    int32_t  handId;
    MTReadout normalized;  // 0..1, origin bottom-left
    float    size;
    int32_t  zero1;
    float    angle, majorAxis, minorAxis;
    MTReadout absolute;    // millimetres
    int32_t  zero2[2];
    float    density;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallback)(MTDeviceRef device, MTTouch *touches, int32_t count,
                                 double timestamp, int32_t frame);

// Returns 0 on success; on failure err holds the reason.
int mt_load(char *err, size_t errlen);
CF_RETURNS_RETAINED CFArrayRef mt_device_list(void);
void mt_register(MTDeviceRef dev, MTContactCallback cb);
void mt_unregister(MTDeviceRef dev, MTContactCallback cb);
void mt_start(MTDeviceRef dev);
void mt_stop(MTDeviceRef dev);
int  mt_is_builtin(MTDeviceRef dev);   // 1/0, or -1 when the function is unavailable

#endif
