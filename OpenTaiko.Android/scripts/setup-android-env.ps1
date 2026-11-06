# setup-android-env.ps1
#
# Installs the toolchain required to build the OpenTaiko Android APK on a fresh
# Windows machine or CI runner, then writes the resolved JAVA_HOME and
# ANDROID_HOME to %TEMP%\opentaiko-android-env.bat so the calling .bat can pick
# them up (powershell child processes can't export env vars back to cmd).
#
# Steps: ensure the .NET android workload, a JDK 17, and the Android SDK
# (accepting licenses and installing platform-tools plus the latest available
# platforms / build-tools). Every step is idempotent — already-present pieces are
# detected and skipped, so the script is safe to re-run locally.
$ErrorActionPreference = "Stop"

$envBat = Join-Path $env:TEMP "opentaiko-android-env.bat"
$androidHome = if ($env:ANDROID_HOME) { $env:ANDROID_HOME }
               else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }

# ---- .NET android workload -------------------------------------------------------
$workloads = & dotnet workload list 2>$null | Out-String
if ($workloads -notmatch "(?m)^\s*android\s") {
    Write-Host "[setup] installing the .NET android workload..."
    & dotnet workload install android
    if ($LASTEXITCODE -ne 0) { throw "dotnet workload install android failed" }
} else {
    Write-Host "[setup] .NET android workload already present"
}

# ---- JDK 17 ----------------------------------------------------------------------
$javaHome = $null
$cands = @(
    "C:\Program Files\Microsoft\jdk-17*",
    "C:\Program Files\Eclipse Adoptium\jdk-17*",
    "C:\Program Files\Java\jdk-17*"
)
foreach ($p in $cands) {
    $h = Get-Item $p -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($h -and (Test-Path (Join-Path $h.FullName "bin\java.exe"))) { $javaHome = $h.FullName; break }
}
if (-not $javaHome -and $env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) {
    $javaHome = $env:JAVA_HOME
}
if (-not $javaHome) {
    Write-Host "[setup] downloading Temurin JDK 17..."
    $tmp = Join-Path $env:TEMP "opentaiko-jdk17.zip"
    Invoke-WebRequest "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse" -OutFile $tmp
    $dst = Join-Path $env:TEMP "opentaiko-jdk17"
    if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($tmp, $dst)
    $javaHome = (Get-ChildItem $dst -Directory | Select-Object -First 1).FullName
}
Write-Host "[setup] JDK : $javaHome"

# ---- Android SDK -----------------------------------------------------------------
$needSdk = -not (Test-Path (Join-Path $androidHome "platforms"))
if ($needSdk) {
    Write-Host "[setup] downloading Android command-line tools..."
    $tmp = Join-Path $env:TEMP "opentaiko-cmdline.zip"
    if (-not (Test-Path $tmp)) {
        Invoke-WebRequest "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" -OutFile $tmp
    }
    $extract = Join-Path $env:TEMP "opentaiko-cmdline"
    if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($tmp, $extract)

    $cli = Join-Path $androidHome "cmdline-tools"
    New-Item -ItemType Directory -Force $cli | Out-Null
    if (Test-Path (Join-Path $cli "latest")) { Remove-Item -Recurse -Force (Join-Path $cli "latest") }
    Move-Item (Join-Path $extract "cmdline-tools") (Join-Path $cli "latest")

    $sdkmgr = Join-Path $cli "latest\bin\sdkmanager.bat"
    $env:ANDROID_HOME = $androidHome
    $env:JAVA_HOME = $javaHome
    $env:PATH = "$javaHome\bin;" + $env:PATH

    Write-Host "[setup] accepting Android SDK licenses..."
    echo y | & $sdkmgr --licenses | Out-Null

    # Install the latest available platform + build-tools so the .NET android
    # workload's (unspecified) target SDK always has a matching platform to build
    # against. Pinning avoids guessing which API level net10.0-android expects.
    $list = & $sdkmgr --list 2>$null
    $apiMatches = $list | Select-String 'platforms;android-(\d+)' |
        ForEach-Object { [int]$_.Matches.Groups[1].Value }
    $latestApi = ($apiMatches | Sort-Object -Descending | Select-Object -First 1)
    $btMatches = $list | Select-String 'build-tools;(\d+\.\d+\.\d+)' |
        ForEach-Object { $_.Matches.Groups[1].Value }
    $latestBt = ($btMatches | Sort-Object -Descending | Select-Object -First 1)

    if (-not $latestApi) { throw "could not determine a platform to install from sdkmanager --list" }
    if (-not $latestBt) { $latestBt = "$latestApi.0.0" }

    Write-Host "[setup] installing platform-tools, platforms;android-$latestApi, build-tools;$latestBt..."
    & $sdkmgr --install "platform-tools" "platforms;android-$latestApi" "build-tools;$latestBt"
    if ($LASTEXITCODE -ne 0) { throw "sdkmanager install failed" }
} else {
    Write-Host "[setup] Android SDK already present at $androidHome"
}

# Resolve the highest installed platform so the build can pin its target SDK to a
# platform we actually have (avoids "platform not found" from the workload default).
$installedApi = (Get-ChildItem (Join-Path $androidHome "platforms") -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^android-(\d+)$' } |
    ForEach-Object { [int]$_.Name.Split('-')[1] } |
    Sort-Object -Descending | Select-Object -First 1)
if (-not $installedApi) { throw "no Android platform found under $androidHome\platforms" }
Write-Host "[setup] target SDK : android-$installedApi"

# ---- write env for the calling .bat ----------------------------------------------
@"
set "JAVA_HOME=$javaHome"
set "ANDROID_HOME=$androidHome"
set "ANDROID_TARGET_SDK_VERSION=$installedApi"
"@ | Set-Content -Path $envBat
Write-Host "[setup] wrote $envBat"
