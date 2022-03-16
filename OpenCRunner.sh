#!/bin/bash

################################################################################
##
## OpenCRunner
##
## A shell script to automatically download, compile and test the performances
## of the OpenCRun runtime developed by Politecnico di Milano.
##
################################################################################

### Global Variables ###########################################################
WORKDIR="`pwd`"
LOGDIR="$WORKDIR/log"
BUILDDIR=""
PREFIX="$HOME/local"
NUM_CPU=`nproc`
BUILD_TYPE=Debug
TIMECMD="/usr/bin/time"
TIMECMDFMT="%E %M %P"
RUNTIME="opencrun"

CMD_COUNT=0
BUILD=0
TEST=0
ALL_TESTS=1
BENCH=0
ALL_BENCH=1
PLOT=0
CLEAN=0
HELP=0

OPT_RELEASE=llvm_v6
OPT_TYPE=0
OPT_PREFIX=0
OPT_CPU=0
OPT_WORKDIR=0
OPT_CMAKE=0
OPT_RUN_UNITTESTS=0
OPT_RUN_BENCHS=0
OPT_RUN_AMD=0
OPT_RUN_SHOC=0
OPT_RUN_RODINIA=0
OPT_RUN_PARBOIL=0
OPT_RUNTIME=0
OPT_PLOT=0

DONE="\e[1m\e[92mDone\e[0m"
ERROR="\e[1m\e[91mError!\e[0m"
################################################################################

#### Git Repos #################################################################
LLVM_REPO=https://github.com/llvm/llvm-project.git
OPENCRUN_REPO=https://github.com/s1kl3/OpenCRun

SHOC_REPO=https://github.com/s1kl3/shoc
RODINIA_REPO=https://github.com/s1kl3/rodinia
PARBOIL_REPO=https://github.com/s1kl3/parboil
AMDAPP_SAMPLES_REPO=https://github.com/s1kl3/AMDAPP_samples
################################################################################

help() {
  echo -e "Usage:\t$0 build [ Build Options ]..."
  echo -e "   or:\t$0 test [Test Options]..."
  echo -e "   or:\t$0 bench [Benchmark Options]..."
  echo -e "   or:\t$0 plot"
  echo -e "   or:\t$0 clean"
  echo -e "   or:\t$0 help\n"

  echo -e "General Options:\n"
  echo -e "\t[--workdir <path>]\t\tLocation for source trees and builds (default: $WORKDIR)\n"

  echo -e "Build Options (Install folder: $PREFIX):\n"
  echo -e "\t[--llvm_v3.7]\t\t\tBuild OpenCRun release for LLVM/Clang 3.7"
  echo -e "\t[--llvm_v3.5]\t\t\tBuild OpenCRun release for LLVM/Clang 3.5"
  echo -e "\t[--llvm_v6]\t\t\tBuild OpenCRun release for LLVM/Clang 6 (default)"
  echo -e "\t[--dev]\t\t\t\tBuild OpenCRun for the latest LLVM/Clang snapshot"
  echo -e "\t[--type <build_type>]\t\tBuild type <Debug|Release|RelWithDebInfo|MinSizeRel> (default: Debug)"
  echo -e "\t[--prefix <install_prefix>]\tInstallation prefix (default: $HOME/local)"
  echo -e "\t[--cmake]\t\t\tBuild with CMake"
  echo -e "\t[--cpu <n>]\t\t\tUse n CPU cores for building (default: $NUM_CPU)\n"

  echo -e "Test Options:\n"
  echo -e "\t[--unittests]\t\t\tRun OpenCRun unittests "
  echo -e "\t[--benchmarks]\t\t\tRun OpenCRun benchmarks"
  echo -e "\t[--cpu <n>]\t\t\tUse n CPU cores for running unittests (default: $NUM_CPU)\n"

  echo -e "Benchmark Options:\n"
  echo -e "\t[--amd]\t\t\t\tRun the AMD SDK benchmarks"
  echo -e "\t[--shoc]\t\t\tRun the SHOC benchmarks"
  echo -e "\t[--rodinia]\t\t\tRun the Rodinia benchmarks"
  echo -e "\t[--parboil]\t\t\tRun the Parboil benchmarks"
  echo -e "\t[--plot]\t\t\tGenerate graphs using GNUPlot"
  echo -e "\t[--runtime <intel|amd>]\t\tRun benchmarks with a runtime other than OpenCRun\n"

  exit 1
}

set_compilers() {
  local NGCC

  case $OPT_RELEASE in
    llvm_v3.5)
      # GCC 4.x is needed
      local GCC_VS=( ".8" ".6" ".4" ".2" "" )
      for i in "${GCC_VS[@]}"
      do
        which "gcc-4$i" >/dev/null
        NGCC=$?
        which "g++-4$i" >/dev/null
        NGCC=${NGCC} || $?
        if [ ${NGCC} -eq 0 ]
        then
          export CC="gcc-4$i"
          export CXX="g++-4$i"
          break
        fi
      done
      ;;
    llvm_v3.7|llvm_v6|dev)
      export CC=gcc
      export CXX=g++
      ;;
    *)
      echo "Error! Invalid OpenCRun release specified: '$OPT_RELEASE'"
      exit 1
      ;;
  esac

  if [ ! -v CC ]
  then
    if [ $OPT_RELEASE -eq "llvm_v3.5" ]
    then
      echo -e "\nGCC 4.x and G++ 4.x (x <= 8) is needed to build the "llvm_v3.5" release!\n"
    else
      echo -e "\nGCC and G++ not found!\n"
    fi

    exit 1
  fi
}

set_env() {
  case $RUNTIME in
    "opencrun")
      PATH="$PREFIX/bin:$PATH"
      LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
      ;;
    "intel")
      PATH=/opt/intel/opencl-sdk/bin:$PATH
      LD_LIBRARY_PATH=/opt/intel/opencl-sdk/lib64
      ;;
    "amd")
      PATH=/opt/AMDAPP/bin:$PATH
      LD_LIBRARY_PATH=/opt/AMDAPP/lib/x86_64
      ;;
    *)
      echo "Error! Invalid OpenCL runtime: '$RUNTIME'"
      exit 1
      ;;
  esac
  
  echo "****************************************************************************"
  echo "PATH = $PATH"
  echo "LD_LIBRARY_PATH = $LD_LIBRARY_PATH"
  echo "****************************************************************************"
}

check_num_cpu() {
  if [[ ( $NUM_CPU -lt 1 ) || ( $NUM_CPU -gt `nproc` ) ]]
  then
    echo -e "\nWrong CPU number (must be 1 <= n <= `nproc`)\n"
    exit 1
  fi

  [[ ( $OPT_CPU -eq 1 ) && ( $TEST -eq 1 ) ]] && \
    echo -e "\nWARNING! The --cpu option is valid only for OpenCRun unittests.\n"
}

check_build_options() {

  case $OPT_RELEASE in
    llvm_v3.5)
      BUILDDIR="build_llvm_v3.5"
      ;;
    llvm_v3.7)
      BUILDDIR="build_llvm_v3.7"
      ;;
    llvm_v6)
      BUILDDIR="build_llvm_v6"
      ;;
    dev)
      BUILDDIR="build_dev"
      ;;
  esac

  case $BUILD_TYPE in
    Debug|Release|RelWithDebInfo|MinSizeRel)
      BUILDDIR="${BUILDDIR}_${BUILD_TYPE}"
      ;;
    *)
      echo "Error! Wrong build type: '$BUILD_TYPE'"
      exit 1
      ;;
  esac

  # CMake is now mandatory for current snapshots of LLVM
  [[ ( $OPT_RELEASE == llvm_v6 ) || ( $OPT_RELEASE == dev ) ]] && OPT_CMAKE=1
}

check_runtime() {
  # This function is used by the "test" command to check whether the runtime DSO
  # is installed or to set BUILD_TYPE and BUILDDIR variables according to the
  # OpenCRun build type specified with the "--type" option to the "build"
  # command.
  case $RUNTIME in
    "opencrun")
      if ! [ -f "$PREFIX/lib/libOpenCRun.so" ]
      then
        echo "libOpenCRun.so not installed. Execute one of the following commands:"
        echo -e "\n\t$0 -c"
        echo -e "\n\t$0 -f\n"
        exit 1
      fi
     
      # We compare static libraries because installed DSOs are always different
      # when using CMake build system.
      for DIR in `find "$WORKDIR/OpenCRun/" -name libOpenCRun.a`
      do
        diff "$PREFIX/lib/libOpenCRun.a" "$DIR" &> /dev/null
        if [ $? -eq 0 ]
        then
          local TMP="`dirname \"${DIR%/lib/libOpenCRun.a}\"`"
          local RELEASE

          [[ $TMP =~ '/build_llvm_v3.5' ]] && RELEASE=llvm_v3.5
          [[ $TMP =~ '/build_llvm_v3.7' ]] && RELEASE=llvm_v3.7
          [[ $TMP =~ '/build_llvm_v6' ]] && RELEASE=llvm_v6
          [[ $TMP =~ '/build_dev' ]] && RELEASE=dev

          if [[ $TMP =~ 'Debug' ]]
          then
            BUILD_TYPE=Debug
          elif [[ $TMP =~ 'Release' ]]
          then
            BUILD_TYPE=Release
          elif [[ $TMP =~ 'RelWithDebInfo' ]]
          then
            BUILD_TYPE=RelWithDebInfo
          elif [[ $TMP =~ 'MinSizeRel' ]]
          then
            BUILD_TYPE=MinSizeRel
          fi

          BUILDDIR="build_${RELEASE}_${BUILD_TYPE}"
        fi
      done
      ;;
    "intel")
      if ! [ -f "/opt/intel/opencl-sdk/lib64/libOpenCL.so" ]
      then
        echo "Intel SDK libOpenCL.so not found in /opt/intel/opencl-sdk/lib64 directory. "
        exit 1
      fi
      ;;
    "amd")
      if ! [ -f "/opt/AMDAPP/lib/x86_64/libOpenCL.so" ]
      then
        echo "AMD SDK libOpenCL.so not found in /opt/AMDAPP/lib/x86_64 directory. "
        exit 1
      fi
      ;;
    *)
      echo "Error! Invalid OpenCL runtime: '$RUNTIME'"
      exit 1
      ;;
  esac
}

clone_repos() {
  local STATUS=0
  local OPENCRUN_TAG
  local BRANCH

  cd "$WORKDIR"
  case $OPT_RELEASE in
    llvm_v3.5)
      BRANCH="release/3.5.x"
      OPENCRUN_TAG="tags/$OPT_RELEASE"
      ;;
    llvm_v3.7)
      BRANCH="release/3.7.x"
      OPENCRUN_TAG="tags/$OPT_RELEASE"
      ;;
    llvm_v6)
      BRANCH="release/6.x"
      OPENCRUN_TAG="tags/$OPT_RELEASE"
      ;;
    dev)
      BRANCH="master"
      OPENCRUN_TAG="origin/dev-sichel"
      ;;
    *)
      echo "Error! Invalid OpenCRun release specified: '$OPT_RELEASE'"
      exit 1
      ;;
  esac

  if ! [ -d llvm-project ]
  then
    git clone $LLVM_REPO && \
      cd llvm-project/llvm && \
      git checkout $BRANCH && \
      cd ../clang && \
      git checkout $BRANCH
  else
    cd llvm-project/llvm
    git checkout master
    git branch | grep -q $BRANCH
    [ $? -eq 0 ] && git branch -f -d $BRANCH
    git pull origin
    git checkout $BRANCH

    cd ../clang
    git checkout master
    git branch | grep -q $BRANCH
    [ $? -eq 0 ] && git branch -f -d $BRANCH
    git pull origin
    git checkout $BRANCH
  fi
  STATUS=$?
  [ $STATUS -ne 0 ] && exit 1
  cd $WORKDIR
  if ! [ -d OpenCRun ]
  then
    git clone $OPENCRUN_REPO && \
      cd OpenCRun && \
      git fetch --all --tags && \
      git checkout tags/$OPT_RELEASE -b $BRANCH && \
      git config push.default tracking
  else
    cd OpenCRun
    git checkout master
    git branch | grep -q $BRANCH
    [ $? -eq 0 ] && git branch -f -d $BRANCH
    git pull origin
    git fetch --all --tags
    git checkout -b $BRANCH $OPENCRUN_TAG
    git config push.default tracking
  fi
  STATUS=$?
  [ $STATUS -ne 0 ] && exit 1

  cd "$WORKDIR"
}

clean() {
  cd "$WORKDIR"

  if [ -d OpenCRun/$BUILDDIR ]
  then
    cd OpenCRun/$BUILDDIR
    make uninstall
    cd "$WORKDIR"
    rm -rf OpenCRun/$BUILDDIR
  fi

  if [ -d llvm-project/$BUILDDIR ]
  then
    cd llvm-project/$BUILDDIR
    make uninstall
    cd "$WORKDIR"
    rm -rf llvm-project/$BUILDDIR
  fi
}

build() {
  cd "$WORKDIR"

  [ -d llvm-project/$BUILDDIR ] || mkdir llvm-project/$BUILDDIR
  cd llvm-project/$BUILDDIR

  if [ $OPT_CMAKE -eq 1 ]
  then
    cmake -G "Ninja" \
      -DLLVM_ENABLE_PROJECTS=clang -G "Unix Makefiles" \
      -DCMAKE_INSTALL_PREFIX=$PREFIX \
      -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
      -DLLVM_ENABLE_RTTI:BOOL=1 \
      -DLLVM_PARALLEL_COMPILE_JOBS:STRING=$NUM_CPU \
      -DLLVM_PARALLEL_LINK_JOBS:STRING=1 \
      ../llvm && \
    cmake --build . && \
    cmake --build . --target install
    [ $? -ne 0 ] && exit 1 
  else
    if [ $BUILD_TYPE == Release ]
    then
      ../llvm-project/configure --prefix="$PREFIX" --enable-optimized
    elif [ $BUILD_TYPE == MinSizeRel ]
    then
      ../llvm-project/configure --prefix="$PREFIX" --enable-optimized --disable-assertions
    elif [ $BUILD_TYPE == RelWithDebInfo ]
    then
      ../llvm-project/configure --prefix="$PREFIX" --enable-optimized --enable-debug-symbols
    else
      ../llvm-project/configure --prefix="$PREFIX"
    fi
    [ $? -ne 0 ] && exit 1
    # So far C++ RTTI is used by OpenCRun
    REQUIRES_RTTI=1 make -j$NUM_CPU && \
    make install
    [ $? -ne 0 ] && exit 1 
  fi

  [ -d "$WORKDIR/OpenCRun/$BUILDDIR" ] || mkdir "$WORKDIR/OpenCRun/$BUILDDIR"
  
  if [ $OPT_CMAKE -eq 1 ]
  then
    cd "$WORKDIR/OpenCRun/$BUILDDIR" && \
      cmake .. \
      -DCMAKE_INSTALL_PREFIX=${HOME}/local \
      -DLLVM_SRC_ROOT=${WORKDIR}/llvm-project/llvm \
      -DLLVM_OBJ_ROOT=${WORKDIR}/llvm-project/$BUILDDIR && \
      cmake --build . && \
      cmake --build . --target install
  else
    cd "$WORKDIR/OpenCRun/autoconf" && ./AutoRegen.sh && cd ../$BUILDDIR
    ../configure --prefix="$PREFIX" --with-llvmsrc="$WORKDIR/llvm-project/llvm" --with-llvmobj="$WORKDIR/llvm-project/$BUILDDIR" && \
      make -j$NUM_CPU && \
      make install
  fi

  if [ $? -eq 0 ]
  then
    echo -e "\n\n"
    echo -e "****************************************************************************"
    echo -e " Add the following lines to your .bashrc (Not needed by \"$0 test\"):\n"
    echo -e " \texport PATH=$HOME/local/bin:\$PATH"
    echo -e " \texport LD_LIBRARY_PATH=$HOME/local/lib:\$LD_LIBRARY_PATH"
    echo -e "****************************************************************************"
  fi

  cd "$WORKDIR"
}

wait_free_cpu() {
  local -n CPUs=$1
  local -n PIDs=$2

  while [ $CPUs -eq 0 ]
  do
    for ((I = 0; I < ${#PIDs[@]}; ++I)) {
      kill -0 ${PIDs[$I]} 2>/dev/null
      if [ $? -ne 0 ]
      then
        [ $CPUs -lt $NUM_CPU ] && FREE_CPU=$(( $CPUs + 1 ))
        PIDs=(${PIDs[@]:0:$I} ${PIDs[@]:$(( $I + 1 ))})
        break
      fi
    }
    sleep 2
  done
}

run_unittests() {
  local UNITTESTS_DIR="$WORKDIR/OpenCRun/$BUILDDIR/unittests" 
  local UNITTESTS=()
  local PID_LIST=()
  local FREE_CPU=$NUM_CPU
  local I

  cd "$WORKDIR"

  if ! [ -d $UNITTESTS_DIR ]
  then
    echo "Tests not found in [${UNITTESTS_DIR}]."
    exit 1
  fi

  UNITTESTS=(`find $UNITTESTS_DIR -type f -executable | sort`)

  [ -d ${LOGDIR} ] || mkdir ${LOGDIR}

  [ -d ${LOGDIR}/Unittests ] || mkdir ${LOGDIR}/Unittests

  for UNITTEST in ${UNITTESTS[@]}
  do
    UNITTEST_NAME=`basename "$UNITTEST"`

    if [ $UNITTEST_NAME == LibraryTests ]
    then
      local FUNCTION_TYPES=(`"$UNITTEST" --gtest_list_tests | grep Functions | sed 's/OCLDev\/\(.*Functions\).*/\1/' | uniq`)

      for FUNCTION_TYPE in ${FUNCTION_TYPES[@]}
      do
        wait_free_cpu FREE_CPU PID_LIST

        "$UNITTEST" --gtest_filter="*${FUNCTION_TYPE}*" &> "$LOGDIR/Unittests/$UNITTEST_NAME-$FUNCTION_TYPE.log" &
        PID_LIST=(${PID_LIST[@]} $!)
        echo "Launched test [$UNITTEST_NAME - $FUNCTION_TYPE]"
        FREE_CPU=$(( $FREE_CPU - 1 ))
      done
    else
      wait_free_cpu FREE_CPU PID_LIST
      
      "$UNITTEST" &> "$LOGDIR/Unittests/$UNITTEST_NAME.log" &
      PID_LIST=(${PID_LIST[@]} $!)
      echo "Launched test [$UNITTEST_NAME]"
      FREE_CPU=$(( $FREE_CPU - 1 ))
    fi

  done

  echo -n "Waiting  for all tests to complete..."
  wait
  echo -e "${DONE}"
  echo -e "\nCheck inside the \"$LOGDIR/Unittests\" folder for results.\n"

  cd "$WORKDIR"
}

run_benchmarks() {
  local BENCHS_DIR="$WORKDIR/OpenCRun/$BUILDDIR/bench"
  local BENCHS=()

  cd "$WORKDIR"

  if ! [ -d $BENCHS_DIR ]
  then
    echo "Benchmarks not found in [${BENCHS_DIR}]."
    exit 1
  fi

  BENCHS=(`find $BENCHS_DIR -type f -executable | sort`)

  [ -d ${LOGDIR}/Benchmarks ] || mkdir "${LOGDIR}/Benchmarks"

  for BENCH in ${BENCHS[@]}
  do
    local BENCH_DIR=`dirname "$BENCH"`
    local BENCH_NAME=`basename "$BENCH"`

    cd "${BENCH_DIR}"
    ./"${BENCH_NAME}" | tee "${LOGDIR}/Benchmarks/${BENCH_NAME}.log"
  done

  cd "$WORKDIR"
}

run_amd() {
  local PKG="AMDSDK"
  local PKG_DIR="$WORKDIR/AMDAPP_samples"
  local PKG_REPO=$AMDAPP_SAMPLES_REPO
  local PKG_TESTS=()
  local FAILED_TESTS=()

  cd "$WORKDIR"

  if ! [ -d $PKG_DIR ]
  then
    echo -n "AMD SDK test package not found. Downloading..."
    
    git clone $PKG_REPO &> /dev/null
    if [ $? -eq 0 ]
    then
      echo -e "${DONE}"
    else
      echo -e "${ERROR}"
      exit 1
    fi
  fi

  if [ $RUNTIME == "opencrun" ]
  then
    for CMAKELST in `find $PKG_DIR -name CMakeLists.txt`
    do
      sed -e 's/HINTS .*include.*/HINTS \$ENV{HOME}\/local\/include \/usr\/local\/include \/usr\/include/' \
        -e 's/NAMES OpenCL$/NAMES OpenCRun/' \
        -e 's/HINTS .*lib.*/HINTS \$ENV{HOME}\/local\/lib \/usr\/local\/lib \/usr\/lib/' \
        -i $CMAKELST
    done
  elif [ $RUNTIME == "intel" ]
  then
    for CMAKELST in `find $PKG_DIR -name CMakeLists.txt`
    do
      sed -e 's/HINTS .*include.*/HINTS \/opt\/intel\/opencl-sdk\/include/' \
        -e 's/NAMES OpenCRun$/NAMES OpenCL/' \
        -e 's/HINTS .*lib.*/HINTS \/opt\/intel\/opencl-sdk\/lib64/' \
        -i $CMAKELST
    done
  elif [ $RUNTIME == "amd" ]
  then
    for CMAKELST in `find $PKG_DIR -name CMakeLists.txt`
    do
      sed -e 's/HINTS .*include.*/HINTS \/opt\/AMDAPP\/include/' \
        -e 's/NAMES OpenCRun$/NAMES OpenCL/' \
        -e 's/HINTS .*lib.*/HINTS \/opt\/AMDAPP\/lib\/x86_64/' \
        -i $CMAKELST
    done
  fi
  
  cd $PKG_DIR
  [ -d build ] || mkdir build
  cd build


  echo -n "Building AMD SDK samples..."
  cmake .. &> /dev/null && make clean &> /dev/null && make -j$NUM_CPU &> /dev/null
  if [ $? -eq 0 ]
  then
    echo -e "${DONE}"
  else
    echo -e "${ERROR}"
    exit 1
  fi

  cd $WORKDIR

  PKG_TESTS=(`find $PKG_DIR/build/bin/ -type f -executable | sort`)

  [ -d $LOGDIR ] || mkdir "$LOGDIR"

  echo "=================================================================================================="  > "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "  _|_|    _|      _|  _|_|_|          _|_|_|  _|_|_|    _|    _|                                  " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|    _|  _|_|  _|_|  _|    _|      _|        _|    _|  _|  _|                                    " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|_|_|_|  _|  _|  _|  _|    _|        _|_|    _|    _|  _|_|                                      " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|    _|  _|      _|  _|    _|            _|  _|    _|  _|  _|                                    " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|    _|  _|      _|  _|_|_|        _|_|_|    _|_|_|    _|    _|                                  " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "==================================================================================================" >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "                                                                                                  " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  printf "%-40s %-8s %-24s %-14s %-10s\n" "TEST" "RESULT" "TIME ([hh:]mm:ss[.cc])" "MAX RMS (MB)" "CPU%"    >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "--------------------------------------------------------------------------------------------------" >> "${LOGDIR}/${RUNTIME}_${PKG}.log"

  for TEST in ${PKG_TESTS[@]}
  do
    local TEST_DIR=`dirname "$TEST"`
    local TEST_NAME=`basename "$TEST"`
    local TEST_RESULT
    local TEST_TIMEM

    echo -en "Running test \"$TEST_NAME\"..."
    cd $TEST_DIR
    $TIMECMD -f "$TIMECMDFMT" -o /tmp/timem \
      ./$TEST_NAME -q &> "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"
    TEST_RESULT=$?
    TEST_TIMEM=($(grep -v Command /tmp/timem))
    rm /tmp/timem
    cd $WORKDIR
    if [ $TEST_RESULT -eq 0 ]
    then
      echo -e "${DONE}"
      rm ${LOGDIR}/"${RUNTIME}_${PKG}_${TEST_NAME}.log"
      printf "%-40s %-8s %-24s %-14s %-10s\n" $TEST_NAME "OK" ${TEST_TIMEM[0]} $(( ${TEST_TIMEM[1]}/1024 )) ${TEST_TIMEM[2]} >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    else
      echo -e "${ERROR}"
      FAILED_TESTS+=(${TEST_NAME})
      printf "%-40s %-8s %-24s %-14s %-10s\n" $TEST_NAME "FAIL" ${TEST_TIMEM[0]} $(( ${TEST_TIMEM[1]}/1024 )) ${TEST_TIMEM[2]} >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    fi
  done

  for TEST_NAME in ${FAILED_TESTS[@]}
  do
    echo -e "\n\n"                                          >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo "========================================"         >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo "$TEST_NAME"                                       >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo "========================================"         >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo -e "\n"                                            >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    cat < "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"    >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    rm "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"
  done

  cd "$WORKDIR"
}

run_shoc() {
  local PKG="SHOC"
  local PKG_DIR="shoc"
  local PKG_REPO=$SHOC_REPO
  local PKG_TESTS=()
  local FAILED_TESTS=()

  cd "$WORKDIR"

  if ! [ -d $PKG_DIR ]
  then
    echo -n "SHOC test package not found. Downloading..."

    git clone $PKG_REPO &> /dev/null
    if [ $? -eq 0 ]
    then
      echo -e "${DONE}"
    else
      echo -e "${ERROR}"
      exit 1
    fi

    cd shoc
    git fetch
    git checkout -b opencrun origin/opencrun
    cd "$WORKDIR"
  else
    if [ -f $PKG_DIR/Makefile ]
    then
      echo -n "Cleaning SHOC..."
      make -C $PKG_DIR clean &> /dev/null
      if [ $? -eq 0 ]
      then
        echo -e "${DONE}"
      else
        echo -e "${ERROR}"
        exit 1
      fi
    fi
  fi

  cd $PKG_DIR

  echo -n "Building SHOC..."
  if [ $RUNTIME == "opencrun" ]
  then
    LDFLAGS="-L$PREFIX/lib -L$WORKDIR/$PKG_DIR/src/opencrun/common" CPPFLAGS="-I$PREFIX/include" \
      ./configure --with-cuda=no --with-mpi=no --with-opencl=no &> /dev/null
  elif [ $RUNTIME == "intel" ]
  then
    LDFLAGS="-L/opt/intel/opencl-sdk/lib64 -L$WORKDIR/$PKG_DIR/src/opencl/common" CPPFLAGS="-I/opt/intel/opencl-sdk/include" \
      ./configure --with-cuda=no --with-mpi=no &> /dev/null
  elif [ $RUNTIME == "amd" ]
  then
    LDFLAGS="-L/opt/AMDAPP/lib/x86_64 -L$WORKDIR/$PKG_DIR/src/opencl/common" CPPFLAGS="-I/opt/AMDAPP/include" \
      ./configure --with-cuda=no --with-mpi=no &> /dev/null
  fi
  make -j$NUM_CPU &> /dev/null
  if [ $? -eq 0 ]
  then
    echo -e "${DONE}"
  else
    echo -e "${ERROR}"
    exit 1
  fi

  cd $WORKDIR
  PKG_TESTS=(`find $PKG_DIR/src/ -type f -executable | sort`)

  [ -d $LOGDIR ] || mkdir "$LOGDIR"

  echo "=================================================================================================="  > "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "  _|_|_|  _|    _|    _|_|      _|_|_|                                                            " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|        _|    _|  _|    _|  _|                                                                  " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "  _|_|    _|_|_|_|  _|    _|  _|                                                                  " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "      _|  _|    _|  _|    _|  _|                                                                  " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|_|_|    _|    _|    _|_|      _|_|_|                                                            " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "==================================================================================================" >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "                                                                                                  " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  printf "%-40s %-8s %-24s %-14s %-10s\n" "TEST" "RESULT" "TIME ([hh:]mm:ss[.cc])" "MAX RMS (MB)" "CPU%"    >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "--------------------------------------------------------------------------------------------------" >> "${LOGDIR}/${RUNTIME}_${PKG}.log"

  for TEST in ${PKG_TESTS[@]}
  do
    local TEST_DIR=`dirname "$TEST"`
    local TEST_NAME=`basename "$TEST"`
    local TEST_RESULT
    local TEST_TIMEM
 
    echo -en "Running test \"$TEST_NAME\"..."
    $TIMECMD -f "$TIMECMDFMT" -o /tmp/timem \
      $TEST &> "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"
    TEST_RESULT=$?
    TEST_TIMEM=($(grep -v Command /tmp/timem))
    rm /tmp/timem
    if [ $TEST_RESULT -eq 0 ]
    then
      echo -e "${DONE}"
      rm "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"
      printf "%-40s %-8s %-24s %-14s %-10s\n" $TEST_NAME "OK" ${TEST_TIMEM[0]} $(( ${TEST_TIMEM[1]}/1024 )) ${TEST_TIMEM[2]} >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    else
      echo -e "${ERROR}"
      FAILED_TESTS+=(${TEST_NAME})
      printf "%-40s %-8s %-24s %-14s %-10s\n" $TEST_NAME "FAIL" ${TEST_TIMEM[0]} $(( ${TEST_TIMEM[1]}/1024 )) ${TEST_TIMEM[2]} >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    fi
  done

  for TEST_NAME in ${FAILED_TESTS[@]}
  do
    echo -e "\n\n"                                          >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo "========================================"         >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo "$TEST_NAME"                                       >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo "========================================"         >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo -e "\n"                                            >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    cat < "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"    >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    rm "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"
  done

  cd "$WORKDIR"
}

run_rodinia() {
  local PKG="Rodinia"
  local PKG_DIR="$WORKDIR/rodinia"
  local PKG_REPO=$RODINIA_REPO
  local PKG_TESTS=()
  local FAILED_TESTS=()
  local VERSION=""

  cd "$WORKDIR"

  if ! [ -d $PKG_DIR ]
  then
    echo -n "Rodinia test package not found. Downloading..."
    
    git clone $PKG_REPO &> /dev/null
    if [ $? -eq 0 ]
    then
      echo -e "${DONE}"
    else
      echo -e "${ERROR}"
      exit 1
    fi

    cd rodinia
    git fetch
    git checkout -b opencrun origin/opencrun
    cd "$WORKDIR"
  fi

  if [ $RUNTIME == "opencrun" ]
  then
    VERSION="opencrun"
  elif [ $RUNTIME == "intel" ]
  then
    sed -i $PKG_DIR/common/make.config \
      -e 's/^\(OPENCL_DIR = \).*/\1\/opt\/intel\/opencl-sdk/' \
      -e 's/^\(OPENCL_INC = \).*/\1\$(OPENCL_DIR)\/include/' \
      -e 's/^\(OPENCL_LIB = \).*/\1\$(OPENCL_DIR)\/lib64 -lOpenCL/'
    
    VERSION="opencl"
  elif [ $RUNTIME == "amd" ]
  then
    sed -i $PKG_DIR/common/make.config \
      -e 's/^\(OPENCL_DIR = \).*/\1\/opt\/AMDAPP/' \
      -e 's/^\(OPENCL_INC = \).*/\1\$(OPENCL_DIR)\/include/' \
      -e 's/^\(OPENCL_LIB = \).*/\1\$(OPENCL_DIR)\/lib\/x86_64 -lOpenCL/'

    VERSION="opencl"
  fi

  echo -n "Building Rodinia..."
  make -C $PKG_DIR clean &> /dev/null &&
    make -j$NUM_CPU -C $PKG_DIR $(echo $VERSION | tr '[:lower:]' '[:upper:]') &> /dev/null
  if [ $? -eq 0 ]
  then
    echo -e "${DONE}"
  else
    echo -e "${ERROR}"
    exit 1
  fi
  
  PKG_TESTS=(`find $PKG_DIR/$VERSION -type f | grep -E 'run(\.sh)?$' | sort`)

  [ -d $LOGDIR ] || mkdir "$LOGDIR"
  echo "=================================================================================================="  > "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|_|_|                    _|  _|            _|                                                    " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|    _|    _|_|      _|_|_|      _|_|_|          _|_|_|                                          " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|_|_|    _|    _|  _|    _|  _|  _|    _|  _|  _|    _|                                          " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|    _|  _|    _|  _|    _|  _|  _|    _|  _|  _|    _|                                          " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|    _|    _|_|      _|_|_|  _|  _|    _|  _|    _|_|_|                                          " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "==================================================================================================" >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "                                                                                                  " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  printf "%-40s %-8s %-24s %-14s %-10s\n" "TEST" "RESULT" "TIME ([hh:]mm:ss[.cc])" "MAX RMS (MB)" "CPU%"    >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "--------------------------------------------------------------------------------------------------" >> "${LOGDIR}/${RUNTIME}_${PKG}.log"

  for TEST in ${PKG_TESTS[@]}
  do
    local TEST_DIR=`dirname "$TEST"`
    local TEST_SCRIPT=`basename "$TEST"`
    local TEST_NAME=`echo $(basename $TEST_DIR)`
    local TEST_RESULT
    local TEST_TIMEM
    
    echo -en "Running test \"$TEST_NAME\"..."
    cd $TEST_DIR
    $TIMECMD -f "$TIMECMDFMT" -o /tmp/timem \
      bash $TEST_SCRIPT &> "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"
    TEST_RESULT=$?
    TEST_TIMEM=($(grep -v Command /tmp/timem))
    rm /tmp/timem
    if [ $TEST_RESULT -eq 0 ]
    then
      echo -e "${DONE}"
      rm "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"
      printf "%-40s %-8s %-24s %-14s %-10s\n" $TEST_NAME "OK" ${TEST_TIMEM[0]} $(( ${TEST_TIMEM[1]}/1024 )) ${TEST_TIMEM[2]} >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    else
      echo -e "${ERROR}"
      FAILED_TESTS+=(${TEST_NAME})
      printf "%-40s %-8s %-24s %-14s %-10s\n" $TEST_NAME "FAIL" ${TEST_TIMEM[0]} $(( ${TEST_TIMEM[1]}/1024 )) ${TEST_TIMEM[2]} >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    fi
    cd "$WORKDIR"
  done

  for TEST_NAME in ${FAILED_TESTS[@]}
  do
    echo -e "\n\n"                                          >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo "========================================"         >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo "$TEST_NAME"                                       >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo "========================================"         >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo -e "\n"                                            >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    cat < "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"    >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    rm "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"
  done

  cd "$WORKDIR"
}

run_parboil() {
  local PKG="Parboil"
  local PKG_DIR="$WORKDIR/parboil"
  local PKG_REPO=$PARBOIL_REPO
  local PKG_TESTS=()
  local FAILED_TESTS=()
  local VERSION=""

  cd "$WORKDIR"

  if ! [ -d $PKG_DIR ]
  then
    echo -n "Parboil test package not found. Downloading..."
    
    git clone $PKG_REPO &> /dev/null
    if [ $? -eq 0 ]
    then
      echo -e "${DONE}"
    else
      echo -e "${ERROR}"
      exit 1
    fi

    cd $PKG_DIR
    git fetch
    git checkout -b opencrun origin/opencrun
    cd "$WORKDIR"
  fi

  if ! [ -f "$PKG_DIR/common/Makefile.conf" ]
  then
    echo -e "\nParboil test suite not available. Check Git repos.\n"
    exit 1
  fi

  if [ $RUNTIME == "opencrun" ]
  then
    VERSION=$RUNTIME
  elif [ $RUNTIME == "intel" ]
  then
    sed -i $PKG_DIR/common/Makefile.conf \
      -e 's/\(OPENCL_PATH=\).*/\1\/opt\/intel\/opencl-sdk/' \
      -e 's/\(OPENCL_LIB_PATH=\).*/\1\$(OPENCL_PATH)\/lib64/'
    
    VERSION="opencl_$RUNTIME"
  elif [ $RUNTIME == "amd" ]
  then
    sed -i $PKG_DIR/common/Makefile.conf \
      -e 's/\(OPENCL_PATH=\).*/\1\/opt\/AMDAPP/' \
      -e 's/\(OPENCL_LIB_PATH=\).*/\1\$(OPENCL_PATH)\/lib\/x86_64/'

    VERSION="opencl_$RUNTIME"
  fi

  if ! [ -d "$PKG_DIR/datasets" ]
  then
    echo -e "\nMissing datasets! Download from http://impact.crhc.illinois.edu/parboil/parboil_download_page.aspx"
    exit 1
  fi

  cd $PKG_DIR
  PKG_TESTS=(`./parboil list | grep '^  ' | sed 's/ *//' | sort`)

  for TEST in ${PKG_TESTS[@]}
  do
    echo -n "Building Parboil (Test: $TEST)..."
    ./parboil clean $TEST &> /dev/null && ./parboil compile $TEST $VERSION &> /dev/null
    if [ $? -eq 0 ]
    then
      echo -e "${DONE}"
    else
      echo -e "${ERROR}"
      exit 1
    fi
  done

  [ -d $LOGDIR ] || mkdir "$LOGDIR"
  
  echo "=================================================================================================="  > "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|_|_|                        _|                  _|  _|                                          " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|    _|    _|_|_|  _|  _|_|  _|_|_|      _|_|        _|                                          " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|_|_|    _|    _|  _|_|      _|    _|  _|    _|  _|  _|                                          " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|        _|    _|  _|        _|    _|  _|    _|  _|  _|                                          " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "_|          _|_|_|  _|        _|_|_|      _|_|    _|  _|                                          " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "==================================================================================================" >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "                                                                                                  " >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  printf "%-40s %-8s %-24s %-14s %-10s\n" "TEST" "RESULT" "TIME ([hh:]mm:ss[.cc])" "MAX RMS (MB)" "CPU%"    >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
  echo "--------------------------------------------------------------------------------------------------" >> "${LOGDIR}/${RUNTIME}_${PKG}.log"

  local PREV_TEST=""
  for TEST in ${PKG_TESTS[@]}
  do
    local TEST_NAME=$TEST
    local TEST_INPUT=(`./parboil describe $TEST | grep "Data sets: " | sed 's/[^:]*: //'`)
    local TEST_RESULT
    local TEST_TIMEM
   
    echo "" > "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"
    for IN in ${TEST_INPUT[@]}
    do
      echo -e "\n___ Data set: $IN ___\n" >> "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"
      echo -en "Running test \"$TEST_NAME\" (Data set: $IN)..."
      $TIMECMD -f "$TIMECMDFMT" -o /tmp/timem \
        ./parboil run $TEST $VERSION $IN &>> "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"
      TEST_RESULT=$?
      TEST_TIMEM=($(grep -v Command /tmp/timem))
      rm /tmp/timem
      echo -e "\n" >> "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"
      if [ $TEST_RESULT -eq 0 ]
      then
        echo -e "${DONE}"
        rm "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"
        printf "%-40s %-8s %-24s %-14s %-10s\n" "$TEST_NAME ($IN)" "OK" ${TEST_TIMEM[0]} $(( ${TEST_TIMEM[1]}/1024 )) ${TEST_TIMEM[2]} \
          >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
      else
        echo -e "${ERROR}"
        [ "$PREV_TEST" != $TEST_NAME ] && FAILED_TESTS+=(${TEST_NAME})
        printf "%-40s %-8s %-24s %-14s %-10s\n" "$TEST_NAME ($IN)" "FAIL" ${TEST_TIMEM[0]} $(( ${TEST_TIMEM[1]}/1024 )) ${TEST_TIMEM[2]} \
          >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
      fi
      PREV_TEST=$TEST_NAME
    done
  done
  
  for TEST_NAME in ${FAILED_TESTS[@]}
  do
    echo -e "\n\n"                                          >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo "========================================"         >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo "$TEST_NAME"                                       >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo "========================================"         >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    echo -e "\n"                                            >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    cat < "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"    >> "${LOGDIR}/${RUNTIME}_${PKG}.log"
    rm "${LOGDIR}/${RUNTIME}_${PKG}_${TEST_NAME}.log"
  done

  cd "$WORKDIR"
}

plot() {
  local LOGS=()
  local PKGS=( "AMDSDK" "SHOC" "Rodinia" "Parboil" )
  local RUNTIMES=( "OpenCRun" "Intel" "AMD" )

  # Data collection
  echo -n -e "\nCollecting data from log files..."

  which gnuplot &> /dev/null
  if [ $? -ne 0 ]
  then
    echo -e "${ERROR}"
    echo -e "\nGNUPlot is not installed.\n"
    exit 1
  fi

  if [ ! -d $LOGDIR ]
  then
    echo -e "${ERROR}"
    echo -e "\nTest directory \"$LOGDIR\" not found. Run command:\n"
    echo -e "\t$0 test\n"
    exit 1
  fi

  for PKG in ${PKGS[@]}
  do
    LOGS+=($(find $LOGDIR -name "*_${PKG}.log"))
  done

  if [ ${#LOGS[@]} -eq 0 ]
  then
    echo -e "${ERROR}"
    echo -e "\nNo test results found in directory \"$LOGDIR\". Run command:\n"
    echo -e "\t$0 test\n"
    exit 1
  fi

  for LOG in ${LOGS[@]}
  do
    local LOGFILE=`basename $LOG`
    local LOGPKG=$(echo $LOGFILE | sed 's/[^_]*_\([^\.]*\)\.log/\1/')
    local LOGRUNTIME="${LOGFILE%"_${LOGPKG}.log"}"

    sed -n -r '/.* (OK|FAIL) .*/,/^$/{/^$/!p}' $LOG | sed 's/%\( \)*$/\1/' | \
      grep -v '[^ ]* FAIL' | \
      awk '{ if (NF == 5) print $1,$3,$4,$5; else if (NF == 6) print $1 $2,$4,$5,$6 }' | \
      while read TEST TIME MAX_RMS AVG_CPU; \
      do \
        printf "%-40s %-24s %-14s %-10s\n" \
        "$TEST" \
        "$(echo $TIME | awk -F: '{ if (NF == 3) print $1*3600+$2*60+$3; else print $1*60+$2 }')" \
        "$MAX_RMS" \
        "$(echo "$AVG_CPU ${NUM_CPU}" | awk '{ print $1/$2 }')"; \
      done > "/tmp/${LOGRUNTIME}_${LOGPKG}.data"
  done
  echo -e "${DONE}"

  local PLOT_TIME
  local PLOT_MAX_RMS
  local PLOT_AVG_CPU
  local DATAFILE
  local CMP_RUNTIMES
  local PT
  local RET

  # Plotting
  echo -n "Creating PDF graph files in '$LOGDIR' directory..."
  for ((I = 0; I < ${#PKGS[@]}; ++I)) {
    PT=7
    PLOT_TIME="plot"
    PLOT_MAX_RMS="plot"
    PLOT_AVG_CPU="plot"
    for RUNTIME in ${RUNTIMES[@]}
    do
      CMP_RUNTIMES=(${RUNTIMES[@]/$RUNTIME})
      DATAFILE="/tmp/$(echo $RUNTIME | tr '[:upper:]' '[:lower:]')_${PKGS[$I]}.data"
      if [ -f $DATAFILE ]
      then
        for CMP_RUNTIME in ${CMP_RUNTIMES[@]}
        do
          CMP_DATAFILE="/tmp/$(echo $CMP_RUNTIME | tr '[:upper:]' '[:lower:]')_${PKGS[$I]}.data"
          [ ! -f $CMP_DATAFILE ] && continue
          for TEST in `awk '{ print $1 }' $DATAFILE`
          do
            grep -q "$TEST " $CMP_DATAFILE
            [ $? -eq 1 ] && sed -i "/^$TEST /d" $DATAFILE
          done
        done

        [ "$PLOT_TIME" != "plot" ] && PLOT_TIME="$PLOT_TIME, "
        [ "$PLOT_MAX_RMS" != "plot" ] && PLOT_MAX_RMS="$PLOT_MAX_RMS, "
        [ "$PLOT_AVG_CPU" != "plot" ] && PLOT_AVG_CPU="$PLOT_AVG_CPU, "
        PLOT_TIME="$PLOT_TIME \"$DATAFILE\" using 2:xtic(1) title \"$RUNTIME\" with points ps 0.5 pt $PT"
        PLOT_MAX_RMS="$PLOT_MAX_RMS \"$DATAFILE\" using 3:xtic(1) title \"$RUNTIME\" with points ps 0.5 pt $PT"
        PLOT_AVG_CPU="$PLOT_AVG_CPU \"$DATAFILE\" using 4:xtic(1) title \"$RUNTIME\" with points ps 0.5 pt $PT"
      fi

      PT=$(($PT + 1))
    done

gnuplot << EOF_TIME
set terminal pdfcairo enhanced
set output "log/time_${PKGS[$I]}.pdf"
set title "${PKGS[$I]} Execution Times" font "{Times:Bold}" offset graph 0,1
set style line 100 lt -1 lc rgb "gray" lw 0.5
set style line 101 lt -1 lc rgb "gray" lw 0.25 dt 3
set grid ytics mytics ls 100, ls 101
set grid xtics
set size 1,1
set logscale y 2
set ylabel "Time (Seconds)" font "{Times, 10}"
set xtics rotate by 45 right font "{Times, 6}"
set ytics font "{Times, 6}"
set mytics
set key outside bottom center width 1.2 font "{Times,8}" box linewidth 0.5
$PLOT_TIME
EOF_TIME

    RET=$?

gnuplot << EOF_MAX_RMS
set terminal pdfcairo enhanced
set output "log/maxrms_${PKGS[$I]}.pdf"
set title "${PKGS[$I]} Maximum Resident Memory Size" font "{Times:Bold}"
set style line 100 lt -1 lc rgb "gray" lw 0.5
set style line 101 lt -1 lc rgb "gray" lw 0.25 dt 3
set grid ytics mytics ls 100, ls 101
set grid xtics
set size 1,1
set ylabel "RMS (MegaByte)" font "{Times, 10}"
set xtics rotate by 45 right font "{Times, 6}"
set ytics font "{Times, 6}"
set mytics
set yrange [0:]
set key outside bottom center width 1.2 font "{Times,8}" box linewidth 0.5
$PLOT_MAX_RMS
EOF_MAX_RMS

    RET=$? || $RET

gnuplot << EOF_AVG_CPU
set terminal pdfcairo enhanced
set output "log/avgcpu_${PKGS[$I]}.pdf"
set title "${PKGS[$I]} Average CPU Usage" font "{Times:Bold}"
set style line 100 lt -1 lc rgb "gray" lw 0.5 
set style line 101 lt -1 lc rgb "gray" lw 0.25 dt 3
set grid ytics mytics ls 100, ls 101
set grid xtics
set size 1,1
set ylabel "CPU Usage (%)" font "{Times, 10}"
set xtics rotate by 45 right font "{Times, 6}"
set ytics font "{Times, 6}"
set mytics
set yrange [0:100]
set key outside bottom center width 1.2 font "{Times,8}" box linewidth 0.5
$PLOT_AVG_CPU
EOF_AVG_CPU

    RET=$? || $RET
    PT=7
  }
  if [ $RET -ne 0 ]
  then
    echo -e "${ERROR}\n"
    echo "Wrong commands provided to GNUPlot!\n"
    exit 1
  fi
  echo -e "${DONE}"

  # Cleanup
  echo -n "Deleting temporary data files from '/tmp' directory..."
  for RUNTIME in ${RUNTIMES[@]}
  do
    for PKG in ${PKGS[@]}
    do
      DATAFILE="/tmp/$(echo $RUNTIME | tr '[:upper:]' '[:lower:]')_$PKG.data"
      [ -f $DATAFILE ] && rm $DATAFILE
    done
  done
  echo -e "${DONE}\n"
}

kill_jobs() {
  PGID=`ps -o pgid= $$ | grep -o '[0-9]*'`
  kill -9 -$PGID
}

if [ $# -eq 0 ]
then
  help
fi

while [ $# -ge 1 ]
do
  ARG="$1"
  case $ARG in
    build)
      CMD_COUNT=$(( $CMD_COUNT + 1 ))
      BUILD=1
      ;;
    bench)
      CMD_COUNT=$(( $CMD_COUNT + 1 ))
      BENCH=1
      ;;
    test)
      CMD_COUNT=$(( $CMD_COUNT + 1 ))
      TEST=1
      ;;
    plot)
      CMD_COUNT=$(( $CMD_COUNT + 1 ))
      PLOT=1
      ;;
    clean)
      CMD_COUNT=$(( $CMD_COUNT + 1 ))
      CLEAN=1
      ;;
    help)
      CMD_COUNT=$(( $CMD_COUNT + 1 ))
      HELP=1
      ;;
    --dev)
      OPT_RELEASE=dev
      ;;
    --llvm_v3.5)
      OPT_RELEASE=llvm_v3.5
      ;;
    --llvm_v3.7)
      OPT_RELEASE=llvm_v3.7
      ;;
    --llvm_v6)
      OPT_RELEASE=llvm_v6
      ;;
    --type)
      OPT_TYPE=1
      BUILD_TYPE="$2"
      shift
      ;;
    --prefix)
      OPT_PREFIX=1
      PREFIX="$2"
      shift
      ;;
    --cmake)
      OPT_CMAKE=1
      ;;
    --cpu)
      OPT_CPU=1
      NUM_CPU=$2
      shift
      ;;
    --workdir)
      OPT_WORKDIR=1
      WORKDIR=`realpath $2`
      if ! [ -d $WORKDIR ]
      then
        echo "Error! Invalid working directory: '$WORKDIR'"
	exit 1
      fi
      LOGDIR=$WORKDIR/log
      shift
      ;;
    --unittests)
      OPT_RUN_UNITTESTS=1
      ALL_TESTS=0
      ;;
    --benchmarks)
      OPT_RUN_BENCHS=1
      ALL_TESTS=0
      ;;
    --amd)
      OPT_RUN_AMD=1
      ALL_BENCH=0
      ;;
    --shoc)
      OPT_RUN_SHOC=1
      ALL_BENCH=0
      ;;
    --rodinia)
      OPT_RUN_RODINIA=1
      ALL_BENCH=0
      ;;
    --parboil)
      OPT_RUN_PARBOIL=1
      ALL_BENCH=0
      ;;
    --runtime)
      OPT_RUNTIME=1
      RUNTIME=$2
      shift
      ;;
    --plot)
      OPT_PLOT=1
      ;;
    *)
      help
      ;;
  esac
  shift
done

trap kill_jobs SIGINT SIGTERM

[ $CMD_COUNT -ne 1 ] && help

[[ ( $BUILD -eq 0 ) && ( ( $OPT_TYPE -eq 1 )     || \
                         ( $OPT_PREFIX -eq 1 )   || \
                         ( $OPT_CMAKE -eq 1 ) ) ]] && \
                         help

[[ ( $TEST -eq 0 ) && ( $ALL_TESTS -eq 0 ) ]] && help

[[ ( $BENCH -eq 0 ) && ( $ALL_BENCH -eq 0 ) ]] && help
[[ ( $BENCH -eq 0 ) && ( ( $OPT_RUNTIME -eq 1 )  || \
                         ( $OPT_PLOT -eq 1 )) ]] && \
                         help

[[ ( $BUILD -eq 0 ) && ( $TEST -eq 0 ) && ( $OPT_CPU -eq 1 ) ]] && help

if [ $BUILD -eq 1 ]
then
  set_compilers
  check_num_cpu
  check_build_options
  clone_repos
  build
  exit 0
fi

if [ $TEST -eq 1 ]
then
  set_env
  check_num_cpu
  check_runtime
  [ $OPT_RUN_UNITTESTS -eq 1 ] && run_unittests
  [ $OPT_RUN_BENCHS -eq 1 ] && run_benchmarks

  if [ $ALL_TESTS -eq 1 ]
  then
    # Warning!!! By default the test command without any
    # option will perform all tests and benchmarks. This
    # may take a lot of time.
    run_unittests
    run_benchmarks
  fi

  [ $OPT_PLOT -eq 1 ] && plot

  exit 0
fi

if [ $BENCH -eq 1 ]
then
  set_env
  check_runtime

  which time &> /dev/null
  if [ $? -eq 1 ]
  then
      echo -e "${ERROR} Install the GNU time command"
      exit 1
  fi


  [ $OPT_RUN_AMD -eq 1 ] && run_amd
  [ $OPT_RUN_SHOC -eq 1 ] && run_shoc
  [ $OPT_RUN_RODINIA -eq 1 ] && run_rodinia
  [ $OPT_RUN_PARBOIL -eq 1 ] && run_parboil

  if [ $ALL_BENCH -eq 1 ]
  then
    # Warning!!! By default the test command without any
    # option will perform all tests and benchmarks. This
    # may take a lot of time.
    run_amd
    run_shoc
    run_rodinia
    run_parboil
  fi

  [ $OPT_PLOT -eq 1 ] && plot

  exit 0
fi

[ $PLOT -eq 1 ] && plot

[ $CLEAN -eq 1 ] && clean

[ $HELP -eq 1 ] && help
