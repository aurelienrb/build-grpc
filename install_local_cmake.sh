#!/usr/bin/env bash

function exit_failure {
    echo "================"
    echo -e "\e[31mERROR: ${1:-"something failed!"}\e[39m" 1>&2
    exit 1
}

function print_info {
    echo -e "\e[36m$1\e[39m"
}

ARCH=`uname -m`
CMAKE_VER=3.6.3
NPROC=`nproc --all`

function build_cmake {
    SRC_DIR=$1
    print_info "Building cmake source..."
    mkdir build-cmake || exit_failure
    pushd build-cmake
    ../$SRC_DIR/bootstrap --prefix=../cmake --parallel=$NPROC || exit_failure
    make -j $NPROC || exit_failure
    make install || exit_failure
    popd
    print_info "Cleaning..."
    rm -rf build-cmake
}

function download_and_install_cmake_package {
    BINARY_TYPE=$1
    # extract version major.minor
    CMAKE_SHORT_VER=`echo $CMAKE_VER | awk -F'.' '{print $1"."$2}'`
    if [[ "$BINARY_TYPE" != "" ]]; then
        print_info "Downloading cmake binary package $BINARY_TYPE..."
        CMAKE_URL="https://www.cmake.org/files/v$CMAKE_SHORT_VER/cmake-$CMAKE_VER-$BINARY_TYPE.tar.gz"
        DOWNLOAD_DIR=cmake
    else
        print_info "Downloading cmake source package..."
        CMAKE_URL="https://www.cmake.org/files/v$CMAKE_SHORT_VER/cmake-$CMAKE_VER.tar.gz"
        DOWNLOAD_DIR=cmake-src
    fi

    mkdir $DOWNLOAD_DIR || exit_failure
    wget --no-check-certificate -O - ${CMAKE_URL} | tar --strip-components=1 -xz -C $DOWNLOAD_DIR || exit_failure
    
    if [[ "$DOWNLOAD_DIR" == "cmake-src" ]]; then
        build_cmake $DOWNLOAD_DIR
        rm -rf cmake-src
        rm -rf build
        
        print_info "Creating cmake package..."
        PKGNAME=cmake-$CMAKE_VER-$ARCH
        GZIP=-9 tar czf $PKGNAME.tar.gz cmake || exit_failure
        print_info "Package $PKGNAME.tar.gz created!"
    fi
}

function get_cmake {
    # find the cmake package to download (binary or source)
    if [[ "$ARCH" == "x86_64" ]]; then
        download_and_install_cmake_package "Linux-$ARCH"
    elif [[ "$ARCH" == "arm"* ]]; then
        download_and_install_cmake_package
    else
        exit_failure "Update script to support architecture $ARCH"
    fi
}

if [[ ! -d "cmake" ]]; then
    get_cmake
fi
