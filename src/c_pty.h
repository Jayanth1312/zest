// zest PTY C interop header
#undef _FORTIFY_SOURCE
#define _FORTIFY_SOURCE 0
#if !defined(_WIN32)
#if defined(__linux__)
#include <pty.h>
#elif defined(__APPLE__)
#include <util.h>
#endif
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <signal.h>
#include <fcntl.h>
#include <errno.h>
#endif
