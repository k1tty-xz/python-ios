#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject *answer(PyObject *self, PyObject *args)
{
    return PyLong_FromLong(42);
}

static PyMethodDef methods[] = {
    {"answer", answer, METH_NOARGS, "Check an external native extension."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT, "_native_check", NULL, -1, methods
};

PyMODINIT_FUNC PyInit__native_check(void)
{
    return PyModule_Create(&module);
}
