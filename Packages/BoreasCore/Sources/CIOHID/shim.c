#include "CIOHID.h"
// The IOHID symbols are provided by IOKit.framework (linked via Package.swift).

void boreas_hid_release(const void *ref) {
    if (ref) CFRelease(ref);
}
