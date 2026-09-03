#include <Python.h>

int
main(int argc, char **argv)
{
    PyConfig config;
    PyStatus status;

    PyConfig_InitPythonConfig(&config);
    config.use_system_logger = 0;

    status = PyConfig_SetBytesArgv(&config, argc, argv);
    if (!PyStatus_Exception(status)) {
        status = Py_InitializeFromConfig(&config);
    }

    PyConfig_Clear(&config);
    if (PyStatus_IsExit(status)) {
        return status.exitcode;
    }
    if (PyStatus_IsError(status)) {
        Py_ExitStatusException(status);
    }

    return Py_RunMain();
}
