#ifndef HOST_DEFS_H
#define HOST_DEFS_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#define __attribute__(x)
#define to_struct(ptr, type, member) ((type *)((char *)(ptr) - offsetof(type, member)))
typedef uintptr_t ppn_t;
#endif
