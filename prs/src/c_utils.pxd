cdef double sigmoid(double x)
cdef double dot(double[::1] v1, double[::1] v2)
cdef double[::1] elementwise_add_mult(double[::1] v1, double[::1] v2, double s)
cdef double clip(double a, double min_value, double max_value)
