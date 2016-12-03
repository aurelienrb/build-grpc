#!/usr/bin/env bash
# Script to build gRPC with support for Travis

# Script parameters:
# 1st arg [optional]: gRPC version (tag/branch) to clone, ex: v1.0.1 (default: master)
GRPCTAG=${1-master}
# 2nd arg [optional]: pass value 'envsetup-only' to do all the build preparation (git clone, cmake download, ...) without doing any build.
readonly BUILD_TYPE=${2-full}
# change default compiler (gcc) via CC/CXX env var
readonly CC=${CC-gcc}
readonly CXX=${CXX-g++}

function exit_failure {
    echo "================"
    echo -e "\e[31mERROR: ${1:-"something failed!"}\e[39m" 1>&2
    exit 1
}

function print_info {
    echo -e "\e[36m$1\e[39m"
}

readonly GRPCDIR=`pwd`/grpc
readonly ARCH=`uname -m`
declare COMPILER=$CC

function check_compiler {
    if [[ "$CC" == "gcc"* ]]; then
        local GCCVER=`$CC -v 2>&1 | grep "gcc version" | awk '{print $3}'`
        print_info "Detected gcc version $GCCVER"
        # build fails with gcc < 4.8
        if [[ ! $GCCVER =~ [5-9].[0-9].[0-9] ]] && [[ ! $GCCVER =~ 4.[8-9].[0-9] ]]; then
            exit_failure "GCC >= 4.8 is required! Restart the script with 'env CC=gcc-5 CXX=g++-5' or similar."
        fi
        COMPILER="gcc-$GCCVER"
    elif [[ "$CC" == "clang"* ]]; then
        # build fails with clang < 3.5
        local CLANGVER=`$CC -v 2>&1 | grep "clang version" | sed 's/^.*clang version *//' | sed 's/-.*//'`
        print_info "Detected clang version $CLANGVER"
        if [[ ! $CLANGVER =~ 3.[5-9].[0-9] ]]; then
            exit_failure "clang >= 3.5 is required! Restart the script with 'env CC=clang-3.5 CXX=clang-3.5' or similar."
        fi
        COMPILER="clang-$CLANGVER"
    else
        exit_failure "Update the script to support compiler '$CC'"
    fi
    print_info "Detected compiler $COMPILER"
}

function check_go {
    go version &> /dev/null || exit_failure "go is missing! run 'sudo apt-get install -y golang'"
}

function check_cmake {
    if ! cmake -version &> /dev/null ; then
        print_info "CMake was not found on the system"
    else
        local CMAKE_VER=`cmake -version | head -n 1`
    fi

    # if no local cmake available, check that global cmake version is 3.x
    # as required to build grpc
    if [[ "$CMAKE_VER" != *"version 3."* ]]; then
        print_info "CMake is missing or existing version is too old, using a local version"
        if [[ ! -d "cmake" ]]; then
            ./install_local_cmake.sh
        fi
    
        if [[ -f "cmake/bin/cmake" ]]; then
            print_info "Found local cmake"
            PATH=`pwd`/cmake/bin:$PATH
        else
            exit_failure "local cmake version not found!"
        fi
    else
        print_info "Using global (system) cmake"
    fi
    # print cmake version
    local CMAKE_VER=`cmake -version | head -n 1`
    print_info "CMake: $CMAKE_VER"
}

function get_grpc_source_code {
    # clone the repo + the submodules
    if [[ ! -d $GRPCDIR ]]; then
        print_info "Could not find grpc source dir, cloning $GRPCTAG from repo"
        git clone -b $GRPCTAG --depth 1 --recursive https://github.com/grpc/grpc.git || exit_failure
    else
        GRPCTAG=`cd $GRPCDIR && git tag`
        if [[ "$GRPCTAG" == "" ]]; then
            GRPCTAG=`cd $GRPCDIR && git rev-parse --abbrev-ref HEAD`
        fi
    fi
    print_info "gRPC source version $GRPCTAG"
}

function patch_for_arm_support {
    # the CMakeFile of boringssl accepts only "armv6" and "armv7-a"
    # which makes it fails with standard values "armv6l" and "armv7l"
    if [[ "$ARCH" == "armv"* ]]; then
        print_info "ARM detected ($ARCH): patching boringssl for better support"
        local CMFILE=$GRPCDIR/third_party/boringssl/CMakeLists.txt
        sed -i -- 's/STREQUAL "armv6"/MATCHES "^armv6*"/g' $CMFILE || exit_failure
        sed -i -- 's/STREQUAL "armv7-a"/MATCHES "^armv7*"/g' $CMFILE || exit_failure
    fi
}

function patch_zlib_makefile {
    # For some reason, when grpc/third_party/zlib/CMakeLists.txt is triggered from grpc build
    # it will make the zlib examples to be built with the system headers of zlib (/usr/include/zlib.h)
    # instead of the local header file.
    # And on old system like on Travis-CI VMs (Ubuntu 14.04) the installed zlib is too old and will make
    # the build to fail. So the quick fix here is to simply remove the build of those examples.

    local CMFILE=$GRPCDIR/third_party/zlib/CMakeLists.txt
    # 1st step: find the line number of the text marking the begining of the example stuff
    local LINE_NUMBER=`awk '/Example binaries/{ print NR; exit }' $CMFILE`
    if [[ "$LINE_NUMBER" != "" ]]; then
        print_info "Patching file '$CMFILE' to fix possible build issue"
        sed -i -n "1,$((LINE_NUMBER-1)) p" $CMFILE
    fi
}

function patch_grpc_makefile {
    # fix missing lib in cmake file (causing link errors on ubuntu 14.04):
    # libgpr.a(time_posix.c.o): In function `now_impl':
    # time_posix.c:(.text+0xe2): undefined reference to `clock_gettime'
    local CMFILE=$GRPCDIR/CMakeLists.txt
    local STR="target_link_libraries(gpr rt)"
    if ! grep -q "$STR" "$CMFILE"; then # avoid applying the patch several times
        echo $STR >> $CMFILE
    fi
}

function patch_protobuf_install_path {
    # fix "make install" issue with protobuf
    local CMFILE=$GRPCDIR/third_party/protobuf/cmake/install.cmake
    #local STR="install(DIRECTORY ${CMAKE_BINARY_DIR}\/${CMAKE_INSTALL_CMAKEDIR}"
    local STR1="install(DIRECTORY \${CMAKE_BINARY_DIR}\/\${"
    local STR2="install(DIRECTORY \${CMAKE_BINARY_DIR}\/third_party\/protobuf\/\${"
    sed -i "s/$STR1/$STR2/g" $CMFILE
}

function create_build_info_file {
    # add some infos about the build env that was used to build this package
    echo "# System used to build this package" > $PCKGDIR/about.txt
    echo "" >> $PCKGDIR/about.txt
    uname -a >> $PCKGDIR/about.txt
    
    echo "" >> $PCKGDIR/about.txt
    echo "# Build time (cmake + make)" >> $PCKGDIR/about.txt
    echo "" >> $PCKGDIR/about.txt
    
    echo "Debug: $DEBUG_BUILD_TIME" >> $PCKGDIR/about.txt
    echo "Release: $RELEASE_BUILD_TIME" >> $PCKGDIR/about.txt
    echo "Total: $TOTAL_BUILD_TIME" >> $PCKGDIR/about.txt
    echo "using $NPROC parallel job(s)" >> $PCKGDIR/about.txt

    echo "" >> $PCKGDIR/about.txt
    echo "# Compiler" >> $PCKGDIR/about.txt
    echo "" >> $PCKGDIR/about.txt
    $CC -v &>> $PCKGDIR/about.txt
    
    echo "" >> $PCKGDIR/about.txt
    echo "# CPU" >> $PCKGDIR/about.txt
    echo "" >> $PCKGDIR/about.txt
    lscpu >> $PCKGDIR/about.txt
}

function create_grpc_package {
    local PCKGDIR=grpc-$GRPCTAG-linux-$COMPILER-$ARCH
    print_info "Preparing package structure '$PCKGDIR'"

    mkdir -p $PCKGDIR/bin || exit_failure
    cp release/grpc_*_plugin $PCKGDIR/bin/
    cp release/third_party/protobuf/protoc $PCKGDIR/bin/

    cp -R $GRPCDIR/include/ $PCKGDIR/include/ || exit_failure
    # add protobud includes + compiler
    mv release/$PROTOBUF_INSTALLDIR/include/* $PCKGDIR/include/ || exit_failure
    mv release/$PROTOBUF_INSTALLDIR/bin/* $PCKGDIR/bin/ || exit_failure

	mkdir -p $PCKGDIR/lib
	cp ./*.a $PCKGDIR/lib/
	rm $PCKGDIR/lib/libgrpc_cronet.a
	rm $PCKGDIR/lib/libgrpc_csharp_ext.a
	rm $PCKGDIR/lib/libgrpc_plugin_support.a
	
	cp third_party/zlib/libz.a $PCKGDIR/lib/
	cp third_party/boringssl/ssl/libssl.a $PCKGDIR/lib/

	# add protobuf libs
	cp $PROTOBUF_INSTALLDIR/lib/*.a $PCKGDIR/lib/

    create_build_info_file

    # compress package
    print_info "Compressing to $PCKGDIR.tar.gz..."
    GZIP=-9 tar czf $PCKGDIR.tar.gz $PCKGDIR || exit_failure
    mv -f $PCKGDIR.tar.gz ..
}

print_info "Starting build type=$BUILD_TYPE"

check_compiler
check_cmake
check_go
get_grpc_source_code
patch_zlib_makefile
patch_grpc_makefile
patch_for_arm_support
patch_protobuf_install_path

print_info "Build env setup complete"

if [[ "$BUILD_TYPE" == "envsetup-only" ]]; then
    print_info "Stopping here because build type=$BUILD_TYPE"
    exit 0
fi

print_info "Compiler variables: CC=$CC CXX=$CXX"

# run make in parallel if possible
readonly NPROC=`nproc --all`
if [[ "$NPROC" -gt "1" ]]; then
    MAKEJ="-j $NPROC"
    print_info "Enabling parallel build for $NPROC cores"
fi

readonly BUILDDIR=grpc-build
readonly PROTOBUF_INSTALLDIR=protobuf-install
# create new build dir
if [[ -d $BUILDDIR ]]; then
    print_info "Cleaning previous build dir"
    rm -rf $BUILDDIR
fi
mkdir $BUILDDIR || exit_failure
pushd $BUILDDIR
# build in release
cmake -DCMAKE_INSTALL_PREFIX=`pwd`/$PROTOBUF_INSTALLDIR -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=14 $GRPCDIR || exit_failure
make $MAKEJ || exit_failure
make install || exit_failure # protobuf
create_grpc_package
popd

print_info "Done!"
