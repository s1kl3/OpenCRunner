
OpenCRunner
===========

A Bash script to assist users installing the [OpenCRun][1] runtime. It allows to
automatically download, build and install all the required stuff in the
following order:

- [LLVM framework][2]
- [Clang compiler frontend][3]
- OpenCRun

Similarly, it can automatically download, compile and run the following
benchmark suites adapted for OpenCRun:

- [Parboil][4]
- [Rodinia][5]
- [SHOC][6]
- [AMD APP SDK samples][7]

Examples
--------

To build and install OpenCRun along with LLVM/Clang v.6 with all their debugging
symbols:

```
./OpenCRunner.sh build
```

The previous command will use the entire set of CPU cores available on the
system to speed up the compilation process. However, the number of cores can be
explicitly specified, as well as the build type:

```
./OpenCRunner.sh build --cpu 4 --type RelWithDebInfo
```

The supported build types are the same expected from any [CMake][8] build (i.e.
Debug, RelWithDebInfo, Release, MinSizeRel).

OpenCRun can also be built for an LLVM/Clang release other than v.6:

```
./OpenCRunner.sh build --llvm_v3.5
```

Both LLVM/Clang 3.5 and 3.7 are supported. Otherwise, a build with the most
recent snapshot can be attempted: 

```
./OpenCRunner.sh build --dev
```

To test the runtime and measure its performances, the script can assist the user
by launching all the OpenCRun unit tests or by running the entire set of
benchmarks from the previously mentioned third party suites. For example, to
run the benchmark suites and plot the measured results (it requires GNUplot):

```
./OpenCRunner.sh bench --plot
```

The same can be done with another OpenCL runtime (Intel or AMD APP):

```
./OpenCRunner.sh bench --runtime intel
```

As usual, to get more help:

```
./OpenCRunner.sh --help
```


[1]: https://github.com/s1kl3/OpenCRun
[2]: https://llvm.org/
[3]: https://clang.llvm.org/
[4]: https://github.com/s1kl3/parboil 
[5]: https://github.com/s1kl3/rodinia
[6]: https://github.com/s1kl3/shoc
[7]: https://github.com/s1kl3/AMDAPP_samples
[8]: https://cmake.org/
