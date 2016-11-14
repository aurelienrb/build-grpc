# Automated builds of gRPC

[![Build Status](https://travis-ci.org/aurelienrb/build-grpc.svg?branch=master)](https://travis-ci.org/aurelienrb/build-grpc)

## Introduction

[gRPC](http://www.grpc.io/) is a nice piece of software, but getting a working version of it can be a challenge! This project provides small scripts that manage all the little details on various systems.

Once the build has completed, the script will generate a compressed package containnig the gRPC & protobuf tools that generate code, plus the headers and static libs required to compile the generated code.

- The x86_64 packages were built via [Travis CI](https://travis-ci.org/) and automatically uploaded to GitHub.
- The ARM packages were built on the targeted device and manually uploaded.

## Binary packages for gRPC

[![Release](https://img.shields.io/github/release/aurelienrb/build-grpc.svg)](https://github.com/aurelienrb/build-grpc/releases)

> Note: gRPC v1.0.0 is not usable because of a bug in the build system (see [#8606](https://github.com/grpc/grpc/issues/8606))

You will find binary packages on the [release page](https://github.com/aurelienrb/build-grpc/releases). The supported platforms are:
- Linux 64 bits (Travis-CI)
  - gcc 4.8.1, 5.4.1, 6.2.0
  - clang 3.5.0, 3.7.1, 3.8.1
- ARMv6 (Raspberry Pi model B)
  - gcc 4.9.2

## What do the scripts do?

The script will:
- install cmake if not available / existing version is too old
- clone grpc source code + its submodules
- detect and prevent possible build issues by patching the source
- build grpc in debug and release
- create a tar.gz package
 
The possible issues that are fixed by the script are:
- dependency BoringSSL (Google fork of OpenSSL) won't build on `armv6l` or `armv7l` such as Raspberry Pi or NVidia Tegra (issue [#8719](https://github.com/grpc/grpc/issues/8719))
- third_party/zlib references system wide zlib when building examples (issue [#8739](https://github.com/grpc/grpc/issues/8739))
- build will fail because of a link error on some systems (Ubuntu 12.04)
- `make install` fails on protobuf when it is part of gRPC

### Requirements to run the script
- must: bash
- must: git
- must: gcc >= 4.8 or clang >= 3.5 (required to build gRPC)
- must: go (`apt-get install golang`)
- recommened: cmake >= 3. If not, the script will download / build it (requires extra time)

---

## Build times

> Note: the reported times include the cmake phase. They are ordered by total build time (lower is better).

#### gcc vs clang on Intel x64 (Travis-CI)

Dual Intel Xeon 2.8GHz (32 logical cores):

|  compiler   | total |  debug | release
|-------------|-------|--------|--------
| clang-3.5.0 | 48 sec| 22 sec | 28 sec 
| clang-3.7.1 | 52 sec| 22 sec | 30 sec 
| gcc-4.8.1   | 55 sec| 20 sec | 33 sec 
| gcc-5.4.1   | 55 sec| 22 sec | 33 sec 
| clang-3.8.1 | 65 sec| 27 sec | 38 sec 
| gcc-6.2.0   | 68 sec| 28 sec | 40 sec 

#### Raspberry Pi 1 Model B

ARMv6 700 MHz (1 logical core):

|  compiler |   total  |  debug   |  release
|-----------|----------|----------|----------
| gcc-4.9.2 | 4h:03min | 2h:22min | 3h:41min 

---

## Lessons learned

I learned many things while working on this project. Here's a quick summary.

### Travis

Using `sudo: false` to run on [container-based infrastructure](https://docs.travis-ci.com/user/migrating-from-legacy/) rather than virtual machines:
- makes each job run almost **6 times faster** via the use of 32 cores!
- makes installation of dependencies much faster (`apt-get install` vs using docker images)
- allows to run in parallel 5 jobs rather than 2 with open source projets
- makes builds start faster after each commit (almost immediately)

As a result, building 6 targets is done in less than 5 minutes rather than +1 hour!

### Bash tricks

- redirecting both stdout and stderr with `&>` rather than `> cmd 2>&1`
  - ```GCCVER=`gcc -v 2>&1 | grep "gcc version" | awk '{print $3}'` ```
- regex testing:
  - `[[ "$GCCVER" == "4."* ]] && [[ $GCCVER =~ 4.[0-7].* ]]`
- testing if a command exists:
  - `go version &> /dev/null || echo "not available!"`
  - `if ! cmake -version &> /dev/null ; then`
- patching a line in a file:
  - `sed -i -- 's/oldtext/newtext/g' $FILENAME`
- truncate a file at line number:
  - `sed --in-place -n "1,$((LINE_NUMBER-1)) p" $FILE`
- use bash built-in variable `$SECONDS` to compute duration of a command:
  - `SECONDS=0`
  - `command`
  - `echo "Duration: $(($SECONDS / 60)) min $(($SECONDS % 60)) sec`  
- use `env` and `CC`/`CXX` environment variables to run make with C/C++ compilers different from the default ones:
  - `env CC=gcc-6 CXX=g++-6 make`
- use `readonly` or `declare -r` to declare read-only variables (modifying them will cause an error)

### Linux

- `nproc` returns the number of physical cores. Use `nproc --all` to get the logical ones.
- While `uname -m` (machine) and `uname -p` (processor) often give the same results, on Raspberry Pi (Raspbian Jessie Lite) `-m` returns `armv6l` while `-p` returns `unknown`.  
