/* The jailbreak exposes these POSIX APIs. Keep version availability checks;
 * remove only the SDK's blanket application-platform prohibitions. */
#include <Availability.h>
#include <sys/cdefs.h>
#undef __API_UNAVAILABLE
#define __API_UNAVAILABLE(...)
#undef __IOS_PROHIBITED
#define __IOS_PROHIBITED
