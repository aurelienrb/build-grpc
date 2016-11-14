$GRPCTAG="v1.0.1"
$GIT="C:\Users\Aurelien\AppData\Local\Atlassian\SourceTree\git_local\bin\git.exe"
$CMAKE="D:\cmake-3.5.2-win32-x86\bin\cmake.exe"
#$MSBUILD = "C:\Windows\Microsoft.NET\Framework64\v3.5\MSBuild.exe"

function exit_failure {
    Write-Error "Something failed!"
}

function get_grpc_source_code {
    if (!(Test-Path -Path grpc)) {
        &$GIT clone -b $GRPCTAG --depth 1 --recursive https://github.com/grpc/grpc.git
        if (!$?) { exit_failure }
        # need to apply some patches
        Add-Content "grpc\CMakeLists.txt" "add_definitions(-D_WIN32_WINNT=0x0600)"
    }
}


get_grpc_source_code

$BUILDDIR="build"
If (Test-Path $BUILDDIR){
	Remove-Item -Recurse -Force $BUILDDIR
}

if (!(Test-Path Env:\VS140COMNTOOLS)) {
    Write-Error "VC++ 2015 is missing!"
}
$MSBUILD ="${env:ProgramFiles(x86)}\MSBuild\14.0\Bin\MSBuild.exe"

mkdir $BUILDDIR
pushd $BUILDDIR

&$CMAKE -Dprotobuf_MSVC_STATIC_RUNTIME=OFF ../grpc
&$MSBUILD grpc.sln /t:grpc++_unsecure /p:Configuration=Debug /p:Platform=Win32
#&$MSBUILD grpc.sln /t:libprotoc /p:Configuration=Debug /p:Platform=Win32
#&$MSBUILD grpc.sln /t:libprotobuf-lite /p:Configuration=Debug /p:Platform=Win32

#copy debug\*.lib
#copy third_party\protobuf\Debug\*.lib

popd
