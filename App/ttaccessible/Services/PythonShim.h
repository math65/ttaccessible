//
//  PythonShim.h
//  ttaccessible
//
//  The embedded Python runtime (Vendor/Python: BeeWare's CPython for macOS) as a handful of plain
//  C calls, so Swift never includes Python.h — its macros would leak into every other bridged
//  header. Python runs in-process: there is no helper executable, so nothing inside the sandbox
//  ever launches a downloaded program. Each call takes and releases the GIL itself, so any
//  thread may call; only ttac_py_start must come first.
//

#ifndef PythonShim_h
#define PythonShim_h

/// Starts the interpreter — isolated: no environment variables, no user site-packages — with
/// `home` as its prefix, trusting `caFile` for HTTPS, and imports yt-dlp from `ytdlpZip`.
/// Returns 0, or -1 with *errorOut set (free it with ttac_py_free). Safe to call again after a
/// failure.
int ttac_py_start(const char *home, const char *caFile, const char *ytdlpZip, char **errorOut);

/// Resolves a web page to something the media streamer can open. Returns a JSON object (title,
/// url, protocol, headers, is_live, extractor, duration), or NULL with *errorOut set.
char *ttac_py_resolve(const char *pageURL, int timeoutSeconds, char **errorOut);

/// Swaps the yt-dlp in use for the one in `ytdlpZip` (a verified update) and returns its
/// version, or NULL with *errorOut set — in which case the previous yt-dlp is loaded again.
char *ttac_py_switch_ytdlp(const char *ytdlpZip, char **errorOut);

/// The version of the yt-dlp in use, or NULL when Python isn't running.
char *ttac_py_ytdlp_version(void);

void ttac_py_free(char *string);

#endif /* PythonShim_h */
