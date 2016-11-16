$GRPCTAG="v1.0.1"
$CMAKE="D:\cmake-3.5.2-win32-x86\bin\cmake.exe"
$MingwBinDir="C:\Qt\Tools\mingw530_32\bin"

function exit_failure {
    Write-Error "Something failed!"
    popd
    exit
}

function create_package {
    $destDir="."
    copy "$MingwBinDir\libgcc_s_dw2-1.dll" $destDir
    copy "$MingwBinDir\libstdc++-6.dll" $destDir
    copy "$MingwBinDir\libwinpthread-1.dll" $destDir
}

function patch_crypto_cpuintel_file {
    Param(
      [string]$srcDir
    )
# patch third_party\boringssl\crypto\cpu-intel.c:115 (add '&& !defined(__MINGW32__)')
#static uint64_t OPENSSL_xgetbv(uint32_t xcr) {
#if defined(OPENSSL_WINDOWS) && !defined(__MINGW32__)
    $file = "$srcDir\third_party\boringssl\crypto\cpu-intel.c"
    $newFileContent = ""
    $previousLine = ""
    $fileWasPatched = $false
    (Get-Content $file) | Foreach-Object {
        if (($previousLine -eq "static uint64_t OPENSSL_xgetbv(uint32_t xcr) {") -and ($_ -eq "#if defined(OPENSSL_WINDOWS)")) {
            $newFileContent = $newFileContent + "#if defined(OPENSSL_WINDOWS) && !defined(__MINGW32__)`n"
            $fileWasPatched = $true
        }
        else {
            $newFileContent = $newFileContent + "$_`n"
        }
        $previousLine = $_
    }
    if ($fileWasPatched) {
        Write-Host "Patching file '$file'"
        $newFileContent | Out-File -Encoding ASCII $file
    }
}

function patch_source_file {
    Param(
      [string]$file,
      [string]$oldValue,
      [string]$newValue
    )
    (Get-Content $file) -replace "$oldValue", "$newValue" | Set-Content $file
}

function patch_grpc_source_code {
    Param(
      [string]$srcDir
    )

    $patchCookieFile = "$srcDir\patched.txt"
    if (Test-Path "$patchCookieFile") {
        Write-Host "gRPC source code already patched"
        return
    }

    $file = "$srcDir\third_party\boringssl\tool\digest.cc"
    patch_source_file $file "#define PATH_MAX MAX_PATH" ""

# third_party\boringssl\ssl\internal.h triggers a warning:
# error: #warning Please include winsock2.h before windows.h [-Werror=cpp]
    $file = "$srcDir\third_party\boringssl\ssl\internal.h"
    patch_source_file $file "#include <winsock2.h>" ""

# grpc\CMakeLists.txt
# au niveau de 'target_link_libraries(grpc' (333); rajouter en dessous:
#if (WIN32)
#  target_link_libraries(grpc Ws2_32)
#endif()
    Add-Content "$srcDir\CMakeLists.txt" "target_link_libraries(grpc Ws2_32)"

# rajouter la même chose en fin de boringssl\ssl\test\CMakeLists.txt:
#if (WIN32)
# target_link_libraries(bssl_shim Ws2_32)
#endif()
    Add-Content "$srcDir\third_party\boringssl\ssl\test\CMakeLists.txt" "target_link_libraries(bssl_shim Ws2_32)"

# append to grpc\third_party\boringssl\tool\CMakeLists.txt
#if (WIN32)
# target_link_libraries(bssl Ws2_32)
#endif()
    Add-Content "$srcDir\third_party\boringssl\tool\CMakeLists.txt" "target_link_libraries(bssl Ws2_32)"

    patch_crypto_cpuintel_file $srcDir

    "mingw-patched" | Out-File -Encoding ASCII $patchCookieFile
}

patch_grpc_source_code "grpc"

$BUILDDIR="build"
If (Test-Path $BUILDDIR){
	Remove-Item -Recurse -Force $BUILDDIR
}

$env:Path = "$PSScriptRoot\nasm;$env:Path"
$env:Path = "$PSScriptRoot\go\bin;$env:Path"
$env:Path = "$PSScriptRoot\perl\perl\bin;$env:Path"
$env:Path = "$MingwBinDir;$env:Path"

# Need to patch third_party\boringssl\crypto\internal.h:130
# - third_party\boringssl\ssl\internal.h:155
# - third_party\boringssl\crypto\bio\bio_test.cc

# alternative: => define __WINCRYPT_H__ pour eviter d'inclure le fichier coupable

# after include <windows.h> or <winsock2.h>
#ifdef X509_NAME
#undef X509_NAME
#endif

# + pour bio_test.cc
#ifdef X509_EXTENSIONS
#undef X509_EXTENSIONS
#endif

$COMMON_C_CXX="-Wno-unknown-pragmas -Wno-unused-result -Wno-attributes -Wno-unused-variable -D__WINCRYPT_H__ -D_WIN32_WINNT=0x0600"
$CMAKE_C_FLAGS="$COMMON_C_CXX -Wno-implicit-function-declaration -Wno-error=sign-compare"
$CMAKE_CXX_FLAGS=$COMMON_C_CXX

mkdir $BUILDDIR
pushd $BUILDDIR

mkdir debug
cd debug

# TODO: fix missing zlib
&$CMAKE -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_FLAGS="$CMAKE_C_FLAGS" -DCMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS" ../../grpc
#if (!$?) {

&mingw32-make -j 4 GOROOT="$PSScriptRoot\go" GOPATH="$PSScriptRoot\go\src"
if (!(Test-Path ".\libgrpc++_reflection.a")) {
    exit_failure
}
cd ..

mkdir release
cd release
&$CMAKE -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$CMAKE_C_FLAGS" -DCMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS" ../../grpc
if (!$?) {
#    exit_failure
}

&mingw32-make -j 4 GOROOT="$PSScriptRoot\go" GOPATH="$PSScriptRoot\go\src"
if (!(Test-Path ".\libgrpc++_reflection.a")) {
    exit_failure
}
cd ..

popd

Write-Host "Done!"
