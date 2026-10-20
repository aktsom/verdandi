/*
 * open_url.h: open a web page or a local file in its default app (/usr/bin/open)
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// url: http(s)://... or an absolute path. no shell is involved; anything else, or a
// string with control characters, is refused. returns 0 if open was started
extern int macos_open_url(const char *url);

#ifdef __cplusplus
}
#endif
