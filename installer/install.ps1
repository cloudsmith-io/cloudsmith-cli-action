#!/usr/bin/env pwsh
# Cloudsmith CLI standalone binary installer for Windows.
#
# Detects the target, verifies the release archive, and installs it into a
# versioned directory. Does not touch PATH or authenticate.
[CmdletBinding()]
param(
    [string]$Version = $(if ($env:CLOUDSMITH_CLI_VERSION) { $env:CLOUDSMITH_CLI_VERSION } else { "latest" }),
    [string]$InstallRoot = $(
        if ($env:CLOUDSMITH_CLI_INSTALL_ROOT) {
            $env:CLOUDSMITH_CLI_INSTALL_ROOT
        }
        elseif ($env:LOCALAPPDATA) {
            Join-Path $env:LOCALAPPDATA "Cloudsmith\CLI"
        }
        else {
            Join-Path $HOME ".local\share\cloudsmith-cli"
        }
    ),
    [string]$Target = $env:CLOUDSMITH_CLI_TARGET,
    [string]$OutputFile = $env:CLOUDSMITH_CLI_OUTPUT_FILE,
    [string]$Repository = $(if ($env:CLOUDSMITH_CLI_REPOSITORY) { $env:CLOUDSMITH_CLI_REPOSITORY } else { "cloudsmith/cli" }),
    [string]$ManifestUrl = $env:CLOUDSMITH_CLI_MANIFEST_URL,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Where releases are downloaded from. Parameters and CLOUDSMITH_CLI_*
# environment variables override the defaults; -ManifestUrl bypasses URL
# construction entirely.
$DownloadBaseUrl = "https://dl.cloudsmith.io/public"
$ManifestNamePrefix = "cloudsmith-cli-manifest"
$script:InstallerUserAgent = "cloudsmith-cli-install-script"

$script:WorkDir = $null
$script:LockStream = $null

if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

function Write-InstallerLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Error.WriteLine("install.ps1: $Message")
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [int]$Attempts = 3
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            return & $Action
        }
        catch {
            if ($attempt -eq $Attempts) {
                throw
            }
            Start-Sleep -Seconds $attempt
        }
    }
}

function Invoke-WithFilesystemRetry {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [ValidateRange(1, [int]::MaxValue)][int]$Attempts = 10,
        [ValidateRange(0, [int]::MaxValue)][int]$DelayMilliseconds = 1000
    )

    # Windows Defender's real-time scan (or Search indexing) can briefly hold
    # a handle on a just-extracted or just-touched directory, and
    # Directory.Move fails outright if any handle is open. Retry only the
    # transient access errors that pattern produces; anything else propagates
    # immediately. The defaults match MSBuild's Copy task, which retries the
    # same two exception types for the same reason.
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            return & $Action
        }
        catch [System.UnauthorizedAccessException], [System.IO.IOException] {
            if ($attempt -eq $Attempts) {
                Write-Warning "Filesystem operation still blocked after $Attempts attempts $DelayMilliseconds ms apart; giving up"
                throw
            }
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }
}

function Test-DownloadUriAllowed {
    param([Parameter(Mandatory = $true)][string]$Uri)

    [System.Uri]$parsedUri = $null
    if (-not [System.Uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref]$parsedUri) -or
        $parsedUri.Scheme -ne [System.Uri]::UriSchemeHttps) {
        throw "install.ps1: URL must use HTTPS: $Uri"
    }
}

function Resolve-DownloadRedirect {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentUri,
        [Parameter(Mandatory = $true)][string]$Location
    )

    $baseUri = [System.Uri]$CurrentUri
    $nextUri = [System.Uri]::new($baseUri, $Location)
    Test-DownloadUriAllowed -Uri $nextUri.AbsoluteUri
    return $nextUri.AbsoluteUri
}

function Get-InstallerWebRequest {
    param([Parameter(Mandatory = $true)][string]$Uri)

    $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Uri)
    $request.AllowAutoRedirect = $false
    $request.UserAgent = $script:InstallerUserAgent
    $request.Timeout = 300000
    $request.ReadWriteTimeout = 300000
    return $request
}

function Invoke-HttpsDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $currentUri = $Uri
    $redirectCount = 0

    while ($true) {
        Test-DownloadUriAllowed -Uri $currentUri

        $request = Get-InstallerWebRequest -Uri $currentUri

        $response = $null
        try {
            try {
                $response = [System.Net.HttpWebResponse]$request.GetResponse()
            }
            catch [System.Net.WebException] {
                if ($_.Exception.Response) {
                    $response = [System.Net.HttpWebResponse]$_.Exception.Response
                }
                else {
                    throw
                }
            }

            $statusCode = [int]$response.StatusCode
            if ($statusCode -ge 200 -and $statusCode -lt 300) {
                $inputStream = $response.GetResponseStream()
                $outputStream = [System.IO.File]::Open(
                    $Destination,
                    [System.IO.FileMode]::Create,
                    [System.IO.FileAccess]::Write,
                    [System.IO.FileShare]::None
                )
                try {
                    $inputStream.CopyTo($outputStream)
                }
                finally {
                    $outputStream.Dispose()
                    if ($inputStream) { $inputStream.Dispose() }
                }
                return
            }

            if ($statusCode -in @(301, 302, 303, 307, 308)) {
                $location = $response.Headers['Location']
                if (-not $location) {
                    throw "install.ps1: redirect response missing Location header: $currentUri"
                }
                $redirectCount++
                if ($redirectCount -gt 10) {
                    throw "install.ps1: too many redirects while downloading: $Uri"
                }

                $currentUri = Resolve-DownloadRedirect -CurrentUri $currentUri -Location $location
                continue
            }

            throw "install.ps1: download failed with HTTP $statusCode`: $currentUri"
        }
        finally {
            if ($response) {
                $response.Dispose()
            }
        }
    }
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if ($env:CLOUDSMITH_CLI_ALLOW_INSECURE_URLS -eq "true") {
        Invoke-WithRetry {
            # Windows PowerShell applies wildcard matching to -OutFile, so
            # download to a temp path and copy to the destination literally.
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $tempFile `
                    -TimeoutSec 300 -UserAgent $script:InstallerUserAgent | Out-Null
                [System.IO.File]::Copy($tempFile, $Destination, $true)
            }
            finally {
                [System.IO.File]::Delete($tempFile)
            }
        }
        return
    }

    Invoke-WithRetry {
        Invoke-HttpsDownload -Uri $Uri -Destination $Destination
    }
}

function Get-KeyValueFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }
        $separator = $trimmed.IndexOf("=")
        if ($separator -le 0) {
            continue
        }
        $key = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim()
        $values[$key] = $value
    }
    return $values
}

function Get-OSArchitecture {
    try {
        return [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    }
    catch {
        $architecture = $env:PROCESSOR_ARCHITEW6432
        if (-not $architecture) {
            $architecture = $env:PROCESSOR_ARCHITECTURE
        }
        return $architecture
    }
}

function Get-DetectedTarget {
    if ($Target) {
        if ($Target -notmatch '^[A-Za-z0-9._-]+$' -or $Target -eq '.' -or $Target -eq '..') {
            throw "install.ps1: invalid target override: $Target"
        }
        return $Target
    }

    if ($env:OS -ne "Windows_NT") {
        throw "install.ps1: this installer is intended for Windows; use install.sh on Unix hosts"
    }

    $architecture = Get-OSArchitecture

    switch -Regex ($architecture) {
        '^(X64|AMD64)$' { return "windows-x86_64" }
        '^(Arm64|ARM64)$' {
            Write-InstallerLog "Windows ARM64 detected; selecting the x86_64 build for Windows emulation"
            return "windows-x86_64"
        }
        default { throw "install.ps1: unsupported Windows architecture: $architecture" }
    }
}

function Test-CloudsmithExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ExpectedVersion
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    try {
        $output = @(& $Path --version 2>&1)
        $exitCode = $LASTEXITCODE
    }
    catch {
        return $false
    }

    if ($exitCode -ne 0) {
        return $false
    }

    if ($ExpectedVersion) {
        foreach ($line in $output) {
            if (([string]$line).Trim() -eq "CLI Package Version: $ExpectedVersion") {
                return $true
            }
        }
        return $false
    }

    return $true
}

function Test-ZipArchive {
    param([Parameter(Mandatory = $true)][string]$Archive)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if (-not $name) {
                continue
            }
            if ($name.StartsWith('/') -or $name -match '^[A-Za-z]:' -or $name -match '(^|/)\.\.(/|$)') {
                throw "install.ps1: unsafe archive entry: $name"
            }
            if ($name -ne 'cloudsmith' -and $name -ne 'cloudsmith/' -and -not $name.StartsWith('cloudsmith/')) {
                throw "install.ps1: unexpected archive entry outside cloudsmith/: $name"
            }
        }
    }
    finally {
        $zip.Dispose()
    }
}

function Write-InstallResult {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedVersion,
        [Parameter(Mandatory = $true)][string]$ResolvedTarget,
        [Parameter(Mandatory = $true)][string]$BinDirectory,
        [Parameter(Mandatory = $true)][string]$Executable
    )

    $lines = @(
        "version=$ResolvedVersion",
        "target=$ResolvedTarget",
        "bin_dir=$BinDirectory",
        "executable=$Executable"
    )

    if ($OutputFile) {
        $parent = Split-Path -Parent $OutputFile
        if ($parent) {
            [void][System.IO.Directory]::CreateDirectory($parent)
        }
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllLines($OutputFile, $lines, $utf8WithoutBom)
    }
    else {
        $lines | ForEach-Object { Write-Output $_ }
    }
}

try {
    if ($Version -notmatch '^[A-Za-z0-9._+-]+$' -or $Version -eq '.' -or $Version -eq '..') {
        throw "install.ps1: invalid version: $Version"
    }
    if ($Repository -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') {
        throw "install.ps1: repository must be OWNER/REPOSITORY"
    }
    if ($InstallRoot.Contains("`n") -or $InstallRoot.Contains("`r")) {
        throw "install.ps1: install root must not contain a newline"
    }

    $resolvedTarget = Get-DetectedTarget
    Write-InstallerLog "detected target $resolvedTarget"
    $script:InstallerUserAgent = "cloudsmith-cli-install-script (Windows; $(Get-OSArchitecture))"

    $temporaryRoot = Join-Path $InstallRoot ".tmp"
    [void][System.IO.Directory]::CreateDirectory($temporaryRoot)
    $script:WorkDir = Join-Path $temporaryRoot ([Guid]::NewGuid().ToString("N"))
    [void][System.IO.Directory]::CreateDirectory($script:WorkDir)

    $manifestFile = Join-Path $script:WorkDir "manifest.txt"
    if (-not $ManifestUrl) {
        $ManifestUrl = "$DownloadBaseUrl/$Repository/raw/names/$ManifestNamePrefix-$resolvedTarget/versions/$Version/manifest.txt"
    }

    Write-InstallerLog "fetching release manifest"
    Invoke-Download -Uri $ManifestUrl -Destination $manifestFile
    $manifest = Get-KeyValueFile -Path $manifestFile

    $schema = [string]$manifest['schema']
    $resolvedVersion = [string]$manifest['version']
    $manifestTarget = [string]$manifest['target']
    $archiveName = [string]$manifest['archive']
    $archiveUrl = [string]$manifest['url']
    $expectedSha256 = ([string]$manifest['sha256']).ToLowerInvariant()

    if ($schema -ne '1') { throw "install.ps1: unsupported manifest schema: $schema" }
    if (-not $resolvedVersion -or $resolvedVersion -notmatch '^[A-Za-z0-9._+-]+$' -or
        $resolvedVersion -eq '.' -or $resolvedVersion -eq '..') {
        throw "install.ps1: manifest contains an invalid version"
    }
    if ($manifestTarget -ne $resolvedTarget) {
        throw "install.ps1: manifest target '$manifestTarget' does not match '$resolvedTarget'"
    }
    if ($Version -ne 'latest' -and $Version -ne $resolvedVersion) {
        throw "install.ps1: manifest resolved '$resolvedVersion', expected '$Version'"
    }
    if (-not $archiveName -or $archiveName -match '[/\\]') {
        throw "install.ps1: manifest contains an invalid archive name"
    }
    if (-not $archiveUrl) { throw "install.ps1: manifest is missing url" }
    if ($expectedSha256 -notmatch '^[0-9a-f]{64}$') {
        throw "install.ps1: manifest contains an invalid SHA-256"
    }

    $finalParent = Join-Path (Join-Path $InstallRoot $resolvedVersion) $resolvedTarget
    $binDirectory = Join-Path $finalParent "cloudsmith"
    $executable = Join-Path $binDirectory "cloudsmith.exe"
    $metadataFile = Join-Path $binDirectory ".cloudsmith-installation"
    [void][System.IO.Directory]::CreateDirectory($finalParent)

    $lockPath = Join-Path $finalParent ".install.lock"
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    while (-not $script:LockStream) {
        try {
            $script:LockStream = [IO.File]::Open(
                $lockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        }
        catch [IO.IOException] {
            if ([DateTime]::UtcNow -ge $deadline) {
                throw "install.ps1: timed out waiting for installation lock: $lockPath"
            }
            Start-Sleep -Seconds 1
        }
    }

    if (-not $Force -and
        (Test-Path -LiteralPath $metadataFile) -and
        (Test-CloudsmithExecutable -Path $executable -ExpectedVersion $resolvedVersion)) {
        $installedMetadata = Get-KeyValueFile -Path $metadataFile
        if ($installedMetadata['archive_sha256'] -eq $expectedSha256) {
            Write-InstallerLog "reusing verified installation $resolvedVersion at $binDirectory"
            Write-InstallResult -ResolvedVersion $resolvedVersion -ResolvedTarget $resolvedTarget -BinDirectory $binDirectory -Executable $executable
            return
        }
    }

    $archiveFile = Join-Path $script:WorkDir $archiveName
    Write-InstallerLog "downloading Cloudsmith CLI $resolvedVersion"
    Invoke-Download -Uri $archiveUrl -Destination $archiveFile

    # Hash via .NET rather than Get-FileHash: concurrent Windows PowerShell
    # startups can race on the module analysis cache and fail cmdlet discovery.
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $archiveStream = [System.IO.File]::OpenRead($archiveFile)
    try {
        $hashBytes = $sha256.ComputeHash($archiveStream)
    }
    finally {
        $archiveStream.Dispose()
        $sha256.Dispose()
    }
    $actualSha256 = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
    if ($actualSha256 -ne $expectedSha256) {
        throw "install.ps1: archive checksum mismatch"
    }
    Write-InstallerLog "archive checksum verified"

    if (-not $archiveName.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase)) {
        throw "install.ps1: unsupported archive format: $archiveName"
    }
    Test-ZipArchive -Archive $archiveFile

    $extractDirectory = Join-Path $script:WorkDir "extract"
    [void][System.IO.Directory]::CreateDirectory($extractDirectory)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($archiveFile, $extractDirectory)

    $stagedDirectory = Join-Path $extractDirectory "cloudsmith"
    $stagedExecutable = Join-Path $stagedDirectory "cloudsmith.exe"
    if (-not (Test-CloudsmithExecutable -Path $stagedExecutable -ExpectedVersion $resolvedVersion)) {
        throw "install.ps1: downloaded Cloudsmith executable failed validation for resolved version $resolvedVersion"
    }

    $installationMetadata = @(
        "schema=1",
        "version=$resolvedVersion",
        "target=$resolvedTarget",
        "archive_sha256=$expectedSha256",
        "manifest_url=$ManifestUrl"
    )
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllLines((Join-Path $stagedDirectory ".cloudsmith-installation"), $installationMetadata, $utf8WithoutBom)

    # Directory.Move treats both paths literally; Move-Item -Destination chokes
    # on wildcard characters like [ ] in the install root.
    $temporaryFinal = Join-Path $finalParent (".cloudsmith.new." + [Guid]::NewGuid().ToString("N"))
    $oldFinal = Join-Path $finalParent (".cloudsmith.old." + [Guid]::NewGuid().ToString("N"))
    Invoke-WithFilesystemRetry { [System.IO.Directory]::Move($stagedDirectory, $temporaryFinal) }

    if (Test-Path -LiteralPath $binDirectory) {
        Invoke-WithFilesystemRetry { [System.IO.Directory]::Move($binDirectory, $oldFinal) }
    }
    try {
        Invoke-WithFilesystemRetry { [System.IO.Directory]::Move($temporaryFinal, $binDirectory) }
    }
    catch {
        if (Test-Path -LiteralPath $oldFinal) {
            try { Invoke-WithFilesystemRetry { [System.IO.Directory]::Move($oldFinal, $binDirectory) } } catch { Write-Warning "Failed to restore previous installation directory during rollback: $_" }
        }
        throw
    }
    if (Test-Path -LiteralPath $oldFinal) {
        Remove-Item -LiteralPath $oldFinal -Recurse -Force
    }

    Write-InstallerLog "installed Cloudsmith CLI $resolvedVersion to $binDirectory"
    Write-InstallResult -ResolvedVersion $resolvedVersion -ResolvedTarget $resolvedTarget -BinDirectory $binDirectory -Executable $executable
}
finally {
    if ($script:LockStream) {
        $lockPath = $script:LockStream.Name
        $script:LockStream.Dispose()
        Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    }
    if ($script:WorkDir -and (Test-Path -LiteralPath $script:WorkDir)) {
        Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
