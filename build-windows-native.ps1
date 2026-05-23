<#
.SYNOPSIS
    Build php_swoole.dll natively on Windows for multiple PHP versions.

.DESCRIPTION
    This script builds the Swoole PHP extension (php_swoole.dll) directly on the
    host machine using Visual Studio Build Tools, php-sdk-binary-tools, and the
    existing winext PowerShell scripts from the Swoole repository.

    It downloads the PHP devel-pack and dependencies for each target PHP version
    and compiles the extension.

    Prerequisites:
    - Visual Studio 2022 (or Build Tools) with C++ workload
    - Git (for cloning php-sdk-binary-tools)
    - Internet access (to download PHP dev-packs and dependencies)

.PARAMETER PhpVersions
    Array of PHP versions to build. Default: @("8.2", "8.3", "8.4", "8.5")

.PARAMETER ToolsPath
    Path for build tools and downloads. Default: C:\tools\phpdev

.PARAMETER OutputPath
    Path for the output DLL files. Default: .\build-output

.PARAMETER ConfArgs
    Configure arguments for Swoole. Default: "--enable-swoole-curl --enable-swoole-thread"

.PARAMETER Deps
    Comma-separated dependency list. Default: "openssl,libcurl,libssh2,zlib,nghttp2,libzstd,brotli"

.EXAMPLE
    .\build-windows-native.ps1
    # Builds for all PHP versions

.EXAMPLE
    .\build-windows-native.ps1 -PhpVersions @("8.4")
    # Builds only for PHP 8.4

.EXAMPLE
    .\build-windows-native.ps1 -PhpVersions @("8.2","8.3") -ConfArgs "--enable-swoole-curl"
    # Builds for PHP 8.2 and 8.3 with only curl support
#>

param (
    [string[]]$PhpVersions = @("8.2", "8.3", "8.4", "8.5"),
    [string]$ToolsPath = "C:\tools\phpdev",
    [string]$OutputPath = ".\build-output",
    [string]$ConfArgs = "--enable-swoole-curl --enable-swoole-thread",
    [string]$Deps = "openssl,libcurl,libssh2,zlib,nghttp2,libzstd,brotli"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$winextDir = Join-Path $scriptDir ".github\workflows\winext"

# VC version mapping
$vcVersionMap = @{
    "8.2" = "vs16"
    "8.3" = "vs16"
    "8.4" = "vs17"
    "8.5" = "vs17"
}

# Colors and logging
function Write-Banner {
    Write-Host ""
    Write-Host "  ==============================================" -ForegroundColor Magenta
    Write-Host "   Swoole Windows DLL Builder (Native)" -ForegroundColor White
    Write-Host "   Build php_swoole.dll for PHP 8.2 - 8.5" -ForegroundColor White
    Write-Host "  ==============================================" -ForegroundColor Magenta
    Write-Host ""
}

function Write-Step { param($msg) Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Err { param($msg) Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "  [INFO] $msg" -ForegroundColor Yellow }

Write-Banner

# ===== Step 1: Check prerequisites =====
Write-Step "Checking prerequisites"

# Check Visual Studio for required versions
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vsWhere)) {
    Write-Err "vswhere.exe not found. Install Visual Studio with C++ workload."
    exit 1
}

$requiredVcVersions = $PhpVersions | ForEach-Object { $vcVersionMap[$_] } | Select-Object -Unique

foreach ($vc in $requiredVcVersions) {
    if ($vc -eq "vs16") {
        $vsPath = & $vsWhere -version "[16.0,17.0)" -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if (-not $vsPath) {
            Write-Err "Visual Studio 2019 (vs16) C++ workload not found. Required for PHP 8.2/8.3."
            exit 1
        }
        Write-Ok "Visual Studio 2019 found: $vsPath"
    }
    elseif ($vc -eq "vs17") {
        $vsPath = & $vsWhere -version "[17.0,18.0)" -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if (-not $vsPath) {
            Write-Err "Visual Studio 2022 (vs17) C++ workload not found. Required for PHP 8.4/8.5."
            exit 1
        }
        Write-Ok "Visual Studio 2022 found: $vsPath"
    }
}

# Check Git
try {
    $gitVer = git --version 2>$null
    Write-Ok "Git: $gitVer"
}
catch {
    Write-Err "Git not found. Please install Git for Windows."
    exit 1
}

# ===== Step 2: Setup php-sdk-binary-tools =====
Write-Step "Setting up php-sdk-binary-tools"

if (-not (Test-Path $ToolsPath)) {
    New-Item -ItemType Directory -Force -Path $ToolsPath | Out-Null
}

$sdkPath = Join-Path $ToolsPath "php-sdk-binary-tools"
if (-not (Test-Path $sdkPath)) {
    Write-Info "Cloning php-sdk-binary-tools..."
    git clone --single-branch --depth=1 https://github.com/php/php-sdk-binary-tools $sdkPath
    if ($LASTEXITCODE -ne 0) { Write-Err "Failed to clone php-sdk-binary-tools"; exit 1 }
}
else {
    Write-Info "Updating php-sdk-binary-tools..."
    git -C $sdkPath pull 2>$null
}
Write-Ok "php-sdk-binary-tools ready at $sdkPath"

# ===== Step 3: Build for each PHP version =====
$results = @{}

foreach ($phpVer in $PhpVersions) {
    Write-Step "Building Swoole for PHP $phpVer"

    $vcVer = $vcVersionMap[$phpVer]
    $phpArch = "x64"
    $phpTs = $true
    $verShort = $phpVer -replace '\.', ''

    Write-Info "PHP $phpVer | VC: $vcVer | Arch: $phpArch | TS: $phpTs"

    # Determine if this is master (PHP 8.5)
    $master = $phpVer
    if ($phpVer -eq "8.6") { $master = "master" }

    # Create a per-version tools path to avoid conflicts
    $verToolsPath = Join-Path $ToolsPath "php$verShort"
    if (-not (Test-Path $verToolsPath)) {
        New-Item -ItemType Directory -Force -Path $verToolsPath | Out-Null
    }

    # Link the shared php-sdk-binary-tools
    $verSdkPath = Join-Path $verToolsPath "php-sdk-binary-tools"
    if (-not (Test-Path $verSdkPath)) {
        # Create junction/symlink to shared SDK
        cmd /c mklink /J "$verSdkPath" "$sdkPath" 2>$null
        if (-not (Test-Path $verSdkPath)) {
            # Fallback: copy
            Copy-Item -Recurse $sdkPath $verSdkPath
        }
    }

    # ----- Download dependencies -----
    Write-Info "Downloading dependencies for PHP $phpVer..."
    $depsList = $Deps -split ','

    try {
        & "$winextDir\deps.ps1" `
            $depsList `
            -MaxTry 3 `
            -ToolsPath $verToolsPath `
            -PhpVer $master `
            -PhpTs $phpTs `
            -PhpArch $phpArch `
            -PhpVCVer $vcVer `
            -Staging $true

        if ($LASTEXITCODE -ne 0) { throw "deps.ps1 failed" }
        Write-Ok "Dependencies downloaded"
    }
    catch {
        Write-Err "Failed to download dependencies for PHP $phpVer : $_"
        $results[$phpVer] = "FAILED (deps)"
        continue
    }

    # ----- Download PHP devel-pack -----
    Write-Info "Downloading PHP $phpVer devel-pack..."
    try {
        if ($master -eq "master") {
            & "$winextDir\devpack_master.ps1" `
                -MaxTry 3 `
                -ToolsPath $verToolsPath `
                -PhpTs $phpTs `
                -PhpArch $phpArch `
                -PhpVCVer $vcVer
        }
        else {
            & "$winextDir\devpack.ps1" `
                -MaxTry 3 `
                -ToolsPath $verToolsPath `
                -PhpVer $phpVer `
                -PhpTs $phpTs `
                -PhpArch $phpArch `
                -PhpVCVer $vcVer
        }

        if ($LASTEXITCODE -ne 0) { throw "devpack download failed" }
        Write-Ok "PHP $phpVer devel-pack ready"
    }
    catch {
        Write-Err "Failed to download devel-pack for PHP $phpVer : $_"
        $results[$phpVer] = "FAILED (devpack)"
        continue
    }

    # ----- Download PHP runtime -----
    Write-Info "Downloading PHP $phpVer runtime..."
    try {
        & "$winextDir\getphp.ps1" `
            -MaxTry 3 `
            -ToolsPath $verToolsPath `
            -PhpVer $phpVer `
            -PhpTs $phpTs `
            -PhpArch $phpArch `
            -PhpVCVer $vcVer

        if ($LASTEXITCODE -ne 0) { throw "getphp failed" }
        Write-Ok "PHP $phpVer runtime downloaded"
    }
    catch {
        Write-Info "PHP runtime download failed (non-fatal, verification will be skipped)"
    }

    # ----- Build the extension -----
    Write-Info "Building Swoole extension..."

    # Create a batch file that sets up the VS + PHP SDK environment and runs the build
    $envBat = Join-Path $verToolsPath "env.bat"
    if (-not (Test-Path $envBat)) {
        Write-Err "env.bat not found at $envBat - devel-pack setup may have failed"
        $results[$phpVer] = "FAILED (no env.bat)"
        continue
    }
    # Force the compiler to Visual C++ 2019 (vs16)
    # Write-Info "Enforcing Visual C++ 2019 (vs16) compiler..."
    # $envContent = Get-Content $envBat
    # $envContent = $envContent -replace '-c\s+(vs\d+|master)', '-c vs16'
    # [System.IO.File]::WriteAllLines($envBat, $envContent)

    # Ensure a clean build by removing any previous phpize artifacts
    $cleanItems = @("configure.bat", "configure.js", "Makefile", "$phpArch")
    foreach ($item in $cleanItems) {
        $itemPath = Join-Path $scriptDir $item
        if (Test-Path $itemPath) {
            Remove-Item -Recurse -Force $itemPath
        }
    }

    # Resolve the devpack path
    $devpackDir = Get-ChildItem $verToolsPath -Directory | Where-Object { $_.Name -like "php-$phpVer*-devel-$vcVer-$phpArch" } | Select-Object -First 1
    if (-not $devpackDir) {
        $devpackDir = Get-ChildItem $verToolsPath -Directory | Where-Object { $_.Name -like "php-*devel*" } | Select-Object -First 1
    }
    $devpackPath = $devpackDir.FullName

    # Create the build command script that will run inside the PHP SDK environment
    $buildBat = Join-Path $verToolsPath "do_build_$verShort.bat"
    # Note: The build.ps1 script sets ExtPath as CWD and calls phpize.bat + configure + nmake
    $buildContent = @"
@echo off
echo === Building Swoole for PHP $phpVer ===
set FIX_PICKLE=1
set TOOLS_PATH=$verToolsPath
set DEVPACK_PATH=$devpackPath
set UNIX_COLOR=1
powershell -ExecutionPolicy Bypass -File "$winextDir\build.ps1" -ExtPath "$scriptDir" -ToolsPath "$verToolsPath" -ExtName swoole $ConfArgs
exit /b %ERRORLEVEL%
"@
    [System.IO.File]::WriteAllLines($buildBat, $buildContent)

    # Create a wrapper batch file that calls env.bat with the build script and captures output
    $wrapperBat = Join-Path $verToolsPath "wrapper_build_$verShort.bat"
    $buildLogFile = Join-Path $verToolsPath "build_$verShort.log"
    $wrapperContent = @"
@echo off
call "$envBat" "$buildBat" > "$buildLogFile" 2>&1
exit /b %ERRORLEVEL%
"@
    [System.IO.File]::WriteAllLines($wrapperBat, $wrapperContent)

    # Run the build through the wrapper
    # env.bat -> phpsdk-starter.bat -t -> do_build.bat -> build.ps1 -> phpize + configure + nmake
    try {
        Write-Info "Invoking build (output logged to $buildLogFile)..."
        Write-Info "  env.bat -> phpsdk-starter.bat -> build.ps1 -> phpize + configure + nmake"

        $buildProcess = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$wrapperBat`"" `
            -Wait -PassThru -NoNewWindow
        
        # Display the build log
        if (Test-Path $buildLogFile) {
            Get-Content $buildLogFile | ForEach-Object { Write-Host "    $_" }
        }

        if ($buildProcess.ExitCode -ne 0) {
            throw "Build process exited with code $($buildProcess.ExitCode)"
        }
        Write-Ok "Build completed"
    }
    catch {
        Write-Err "Build failed for PHP $phpVer : $_"
        # Show build log tail
        if (Test-Path $buildLogFile) {
            Write-Info "Last 30 lines of build log:"
            Get-Content $buildLogFile -Tail 30 | ForEach-Object { Write-Host "    $_" }
        }
        $results[$phpVer] = "FAILED (build)"
        continue
    }

    # Copy dependency DLLs to PHP directory so that verification/local running works
    $phpBinDir = "$verToolsPath\php"
    if (Test-Path $phpBinDir) {
        Write-Info "Copying dependency DLLs to PHP directory..."
        $depsBinDir = "$verToolsPath\deps\bin"
        if (Test-Path $depsBinDir) {
            Get-ChildItem -Path $depsBinDir -Filter "*.dll" | ForEach-Object {
                Copy-Item $_.FullName -Destination $phpBinDir -Force
            }
        }
    }

    # ----- Collect output -----
    $outDir = Join-Path $scriptDir "build-output\php$verShort"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    # Look for the DLL in expected locations
    $tsDir = if ($phpTs) { "Release_TS" } else { "Release" }
    $dllSearchPaths = @(
        "$scriptDir\$phpArch\$tsDir\php_swoole.dll",
        "$scriptDir\x64\Release_TS\php_swoole.dll",
        "$scriptDir\x64\Release\php_swoole.dll"
    )

    $dllFound = $false
    foreach ($dllPath in $dllSearchPaths) {
        if (Test-Path $dllPath) {
            Copy-Item $dllPath "$outDir\php_swoole.dll" -Force
            if (Test-Path "$phpBinDir\ext") {
                Copy-Item $dllPath "$phpBinDir\ext\php_swoole.dll" -Force
                Write-Ok "DLL copied to PHP extension directory: $phpBinDir\ext\php_swoole.dll"
            }
            $size = [math]::Round((Get-Item $dllPath).Length / 1MB, 2)
            Write-Ok "DLL found and copied: $outDir\php_swoole.dll ($size MB)"
            $results[$phpVer] = "SUCCESS ($size MB)"
            $dllFound = $true
            break
        }
    }

    if (-not $dllFound) {
        # Recursive search
        $foundDll = Get-ChildItem -Recurse -Filter "php_swoole.dll" -Path $scriptDir -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundDll) {
            Copy-Item $foundDll.FullName "$outDir\php_swoole.dll" -Force
            if (Test-Path "$phpBinDir\ext") {
                Copy-Item $foundDll.FullName "$phpBinDir\ext\php_swoole.dll" -Force
                Write-Ok "DLL copied to PHP extension directory: $phpBinDir\ext\php_swoole.dll"
            }
            $size = [math]::Round($foundDll.Length / 1MB, 2)
            Write-Ok "DLL found at $($foundDll.FullName) and copied ($size MB)"
            $results[$phpVer] = "SUCCESS ($size MB)"
        }
        else {
            Write-Err "php_swoole.dll not found after build"
            $results[$phpVer] = "FAILED (no DLL output)"
        }
    }


    # ----- Verify (if PHP runtime available) -----
    $phpExe = "$verToolsPath\php\php.exe"
    if (Test-Path $phpExe) {
        $dllOutputPath = "$outDir\php_swoole.dll"
        if (Test-Path $dllOutputPath) {
            Write-Info "Verifying extension..."
            $verifyResult = & $phpExe -d "extension=$dllOutputPath" --ri swoole 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "Extension verification passed"
                $verifyResult | Select-Object -First 5 | ForEach-Object { Write-Host "    $_" }
            }
            else {
                Write-Info "Verification returned non-zero (may need dependency DLLs at runtime)"
            }
        }
    }
}

# ===== Summary =====
Write-Host ""
Write-Host "  ==============================================" -ForegroundColor Magenta
Write-Host "   BUILD SUMMARY" -ForegroundColor White
Write-Host "  ==============================================" -ForegroundColor Magenta
Write-Host ""

$allOk = $true
foreach ($ver in $PhpVersions) {
    $status = $results[$ver]
    $verShort = $ver -replace '\.', ''
    if ($status -like "SUCCESS*") {
        Write-Host "  PHP $ver : " -NoNewline -ForegroundColor White
        Write-Host $status -ForegroundColor Green
        Write-Host "           -> build-output\php$verShort\php_swoole.dll" -ForegroundColor Gray
    }
    else {
        Write-Host "  PHP $ver : " -NoNewline -ForegroundColor White
        $displayStatus = if ($status) { $status } else { "NOT BUILT" }
        Write-Host $displayStatus -ForegroundColor Red
        $allOk = $false
    }
}

Write-Host ""
if ($allOk) {
    Write-Host "  All builds completed successfully!" -ForegroundColor Green
}
else {
    Write-Host "  Some builds failed. Check logs in $ToolsPath for details." -ForegroundColor Yellow
}
Write-Host ""

exit ([int](-not $allOk))
