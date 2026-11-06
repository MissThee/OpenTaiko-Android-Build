@echo off
REM ===========================================================================
REM build-android.bat - Build the OpenTaiko Android APK on Windows / a CI runner.
REM
REM Installs the .NET android workload, JDK 17 and the Android SDK (if missing,
REM via OpenTaiko.Android\scripts\setup-android-env.ps1), fetches the BASS /
REM FFmpeg natives + the vendored FFmpeg.AutoGen source, then builds a signed
REM Release APK via OpenTaiko.Android\scripts\build.ps1.
REM
REM Output (stable path for upload): OpenTaiko.Android.apk  (repo root)
REM ===========================================================================
setlocal EnableExtensions
cd /d "%~dp0"

echo [build-android] Setting up the Android toolchain...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0OpenTaiko.Android\scripts\setup-android-env.ps1"
if errorlevel 1 exit /b 1

call "%TEMP%\opentaiko-android-env.bat"

echo [build-android] Building the signed Release APK...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0OpenTaiko.Android\scripts\build.ps1" -Release -Clean -AndroidSdk "%ANDROID_HOME%" -JavaSdk "%JAVA_HOME%"
if errorlevel 1 exit /b 1

echo [build-android] Locating the signed APK...
set "APK="
for /f "delims=" %%a in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem '%~dp0OpenTaiko.Android\bin\Release\net10.0-android' -Recurse -Filter '*-Signed.apk' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { $_.FullName }"') do set "APK=%%a"
if not defined APK (
    echo [build-android] ERROR: signed APK not found
    exit /b 1
)
echo [build-android] APK: %APK%
copy /Y "%APK%" "%~dp0OpenTaiko.Android.apk" >nul
echo [build-android] Copied to %~dp0OpenTaiko.Android.apk

echo [build-android] Done.
endlocal
