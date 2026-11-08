#ifndef CIOHID_H
#define CIOHID_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

// Private IOKit HID event-system API (read-only temperature services).
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;

#define kBoreasIOHIDEventTypeTemperature 15
#define kBoreasIOHIDEventFieldTemperatureLevel (15 << 16)
#define kBoreasHIDPrimaryUsagePage 0xff00
#define kBoreasHIDPrimaryUsage 5

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client) CF_RETURNS_RETAINED;
CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key) CF_RETURNS_RETAINED;
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

// The HID refs are plain struct pointers (no ARC); release them with this helper.
void boreas_hid_release(const void *ref);

#endif
