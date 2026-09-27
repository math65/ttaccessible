//
//  PythonShim.c
//  ttaccessible
//

#include <Python/Python.h>   // first: Python.h must precede every other header
#include <stdlib.h>
#include <string.h>
#include "PythonShim.h"

// Loaded into __main__ once. Everything that knows about yt-dlp lives here, in Python; the C
// side only moves strings in and out.
static const char *kBootstrap =
    "import importlib, json, sys\n"
    "_ttac_path = None\n"
    "\n"
    "def _ttac_use(path):\n"
    "    # Forget any loaded yt-dlp, put `path` first on sys.path, and import it fresh.\n"
    "    global _ttac_path\n"
    "    for name in list(sys.modules):\n"
    "        if name.split('.')[0] in ('yt_dlp', 'yt_dlp_ejs'):\n"
    "            del sys.modules[name]\n"
    "    if _ttac_path in sys.path:\n"
    "        sys.path.remove(_ttac_path)\n"
    "    sys.path.insert(0, path)\n"
    "    importlib.invalidate_caches()\n"
    "    import yt_dlp\n"
    "    _ttac_path = path\n"
    "    return yt_dlp.version.__version__\n"
    "\n"
    "# A direct link or an HLS playlist: what FFmpeg, inside the TeamTalk streamer, can open.\n"
    "_FORMAT = ('bestaudio[protocol^=http]/bestaudio[protocol^=m3u8]/'\n"
    "           'best[protocol^=http]/best[protocol^=m3u8]/bestaudio/best')\n"
    "\n"
    "def _ttac_resolve(url, timeout):\n"
    "    import yt_dlp\n"
    "    options = {'quiet': True, 'no_warnings': True, 'noplaylist': True,\n"
    "               'playlist_items': '1', 'skip_download': True, 'cachedir': False,\n"
    "               'format': _FORMAT, 'socket_timeout': timeout}\n"
    "    with yt_dlp.YoutubeDL(options) as ydl:\n"
    "        info = ydl.extract_info(url, download=False)\n"
    "    if info.get('_type') == 'playlist':\n"
    "        info = next((entry for entry in (info.get('entries') or []) if entry), None)\n"
    "        if info is None:\n"
    "            raise ValueError('nothing playable on this page')\n"
    "    media = info.get('url') or ''\n"
    "    if not media and info.get('requested_formats'):\n"
    "        media = info['requested_formats'][0].get('url') or ''\n"
    "    if not media:\n"
    "        raise ValueError('nothing playable on this page')\n"
    "    return json.dumps({'title': info.get('title') or '', 'url': media,\n"
    "                       'protocol': info.get('protocol') or '',\n"
    "                       'headers': info.get('http_headers') or {},\n"
    "                       'is_live': bool(info.get('is_live')),\n"
    "                       'extractor': info.get('extractor_key') or '',\n"
    "                       'duration': info.get('duration')})\n"
    "\n"
    "def _ttac_version():\n"
    "    import yt_dlp\n"
    "    return yt_dlp.version.__version__\n";

/// __main__'s globals, where the bootstrap's functions live. Borrowed; valid once started.
static PyObject *mainGlobals = NULL;
static int bootstrapLoaded = 0;

static char *duplicateUTF8(PyObject *object) {
    const char *text = PyUnicode_AsUTF8(object);
    return text ? strdup(text) : NULL;
}

/// The pending Python exception as text, clearing it. The GIL must be held.
static char *takeErrorText(void) {
    PyObject *exception = PyErr_GetRaisedException();
    char *message = NULL;
    if (exception) {
        PyObject *text = PyObject_Str(exception);
        if (text) {
            message = duplicateUTF8(text);
            Py_DECREF(text);
        }
        Py_DECREF(exception);
    }
    PyErr_Clear();
    return message ? message : strdup("unknown Python error");
}

/// Calls a bootstrap function with `arguments` (a new reference, consumed) and returns its str
/// result as a malloc'd copy. The GIL must be held.
static char *callBootstrap(const char *function, PyObject *arguments, char **errorOut) {
    PyObject *callable = mainGlobals ? PyDict_GetItemString(mainGlobals, function) : NULL;
    if (!callable || !arguments) {
        Py_XDECREF(arguments);
        if (errorOut) *errorOut = strdup("the Python bootstrap is not loaded");
        return NULL;
    }
    PyObject *result = PyObject_CallObject(callable, arguments);
    Py_DECREF(arguments);
    if (!result) {
        char *message = takeErrorText();
        if (errorOut) *errorOut = message; else free(message);
        return NULL;
    }
    char *text = PyUnicode_Check(result) ? duplicateUTF8(result) : NULL;
    Py_DECREF(result);
    if (!text && errorOut) *errorOut = strdup("unexpected result from Python");
    return text;
}

int ttac_py_start(const char *home, const char *caFile, const char *ytdlpZip, char **errorOut) {
    if (!Py_IsInitialized()) {
        // OpenSSL reads this itself, so the isolated configuration can't hide it.
        setenv("SSL_CERT_FILE", caFile, 1);
        PyConfig config;
        PyConfig_InitIsolatedConfig(&config);
        config.write_bytecode = 0;           // the framework sits in the signed, read-only bundle
        config.install_signal_handlers = 0;  // the app owns its signals
        PyStatus status = PyConfig_SetBytesString(&config, &config.home, home);
        if (!PyStatus_Exception(status)) {
            status = Py_InitializeFromConfig(&config);
        }
        PyConfig_Clear(&config);
        if (PyStatus_Exception(status)) {
            if (errorOut) *errorOut = strdup(status.err_msg ? status.err_msg : "Python failed to start");
            return -1;
        }
        // The main thread holds the GIL after initialisation; every call below takes it the
        // same way, so hand it back now.
        PyEval_SaveThread();
    }

    PyGILState_STATE gil = PyGILState_Ensure();
    int result = -1;
    if (!bootstrapLoaded) {
        mainGlobals = PyModule_GetDict(PyImport_AddModule("__main__"));
        PyObject *ran = PyRun_String(kBootstrap, Py_file_input, mainGlobals, mainGlobals);
        if (ran) {
            Py_DECREF(ran);
            bootstrapLoaded = 1;
        } else {
            char *message = takeErrorText();
            if (errorOut) *errorOut = message; else free(message);
        }
    }
    if (bootstrapLoaded) {
        char *version = callBootstrap("_ttac_use", Py_BuildValue("(s)", ytdlpZip), errorOut);
        result = version ? 0 : -1;
        free(version);
    }
    PyGILState_Release(gil);
    return result;
}

char *ttac_py_resolve(const char *pageURL, int timeoutSeconds, char **errorOut) {
    if (!bootstrapLoaded) {
        if (errorOut) *errorOut = strdup("Python is not running");
        return NULL;
    }
    PyGILState_STATE gil = PyGILState_Ensure();
    char *json = callBootstrap("_ttac_resolve", Py_BuildValue("(si)", pageURL, timeoutSeconds), errorOut);
    PyGILState_Release(gil);
    return json;
}

char *ttac_py_switch_ytdlp(const char *ytdlpZip, char **errorOut) {
    if (!bootstrapLoaded) {
        if (errorOut) *errorOut = strdup("Python is not running");
        return NULL;
    }
    PyGILState_STATE gil = PyGILState_Ensure();
    PyObject *previous = PyDict_GetItemString(mainGlobals, "_ttac_path");  // borrowed
    char *previousPath = (previous && PyUnicode_Check(previous)) ? duplicateUTF8(previous) : NULL;
    char *version = callBootstrap("_ttac_use", Py_BuildValue("(s)", ytdlpZip), errorOut);
    if (!version && previousPath) {
        // The update didn't import: go back to the yt-dlp that worked.
        free(callBootstrap("_ttac_use", Py_BuildValue("(s)", previousPath), NULL));
    }
    free(previousPath);
    PyGILState_Release(gil);
    return version;
}

char *ttac_py_ytdlp_version(void) {
    if (!bootstrapLoaded) return NULL;
    PyGILState_STATE gil = PyGILState_Ensure();
    char *version = callBootstrap("_ttac_version", PyTuple_New(0), NULL);
    PyGILState_Release(gil);
    return version;
}

void ttac_py_free(char *string) {
    free(string);
}
