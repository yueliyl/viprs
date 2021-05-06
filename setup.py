from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize
from Cython.Distutils import build_ext
import numpy as np
import os
import platform

#if platform.system() == 'Darwin':
#    os.environ['CC'] = '/usr/local/opt/llvm/bin/clang++'

ext_modules = cythonize([
    Extension("prs.src.test",
              ["prs/src/test.pyx"],
              libraries=["m"],
              extra_compile_args=["-ffast-math"]),
    Extension("prs.src.c_utils",
              ["prs/src/c_utils.pyx"],
              libraries=["m"],
              extra_compile_args=["-ffast-math"]),
    Extension("prs.src.run_stats",
              ["prs/src/run_stats.pyx"],
              libraries=["m"],
              extra_compile_args=["-ffast-math"]),
    Extension("prs.src.PRSModel",
              ["prs/src/PRSModel.pyx"],
              libraries=["m"],
              extra_compile_args=["-ffast-math"]),
    Extension("prs.src.vem_c_opt",
              ["prs/src/vem_c_opt.pyx"],
              libraries=["m"],
              extra_compile_args=["-ffast-math", "-fopenmp"],
              extra_link_args=["-lomp"]),
    Extension("prs.src.gibbs_c",
              ["prs/src/gibbs_c.pyx"],
              libraries=["m"],
              extra_compile_args=["-ffast-math", "-fopenmp"],
              extra_link_args=["-lomp"]),
    Extension("prs.src.gibbs_c_sbayes",
              ["prs/src/gibbs_c_sbayes.pyx"],
              libraries=["m"],
              extra_compile_args=["-ffast-math", "-fopenmp"],
              extra_link_args=["-lomp"]),
    Extension("prs.src.vem_c_sbayes",
              ["prs/src/vem_c_sbayes.pyx"],
              libraries=["m"],
              extra_compile_args=["-ffast-math", "-fopenmp"],
              extra_link_args=["-lomp"]),
    Extension("prs.src.vem_c_sbayes_infinitesimal",
              ["prs/src/vem_c_sbayes_infinitesimal.pyx"],
              libraries=["m"],
              extra_compile_args=["-ffast-math", "-fopenmp"],
              extra_link_args=["-lomp"]),
    Extension("prs.src.vem_c_sbayes_opt",
              ["prs/src/vem_c_sbayes_opt.pyx"],
              libraries=["m"],
              extra_compile_args=["-ffast-math", "-fopenmp"],
              extra_link_args=["-lomp"]),
    Extension("prs.src.vem_c",
              ["prs/src/vem_c.pyx"],
              libraries=["m"],
              extra_compile_args=["-ffast-math", "-fopenmp"],
              extra_link_args=["-lomp"]),
    Extension("prs.src.vem_c_w_priors",
              ["prs/src/vem_c_w_priors.pyx"],
              libraries=["m"],
              extra_compile_args=["-ffast-math", "-fopenmp"],
              extra_link_args=["-lomp"]),
    Extension("prs.src.vem_c_cs",
              ["prs/src/vem_c_cs.pyx"],
              libraries=["m"],
              extra_compile_args=["-ffast-math", "-fopenmp"],
              extra_link_args=["-lomp"])
], language_level="3")

setup(name="prs",
      cmdclass={"build_ext": build_ext},
      ext_modules=ext_modules,
      include_dirs=[np.get_include()],
      compiler_directives={'boundscheck': False, 'wraparound': False,
                           'nonecheck': False, 'cdivision': True},
      script_args=["build_ext"],
      options={'build_ext': {'inplace': True, 'force': True}}
      )

