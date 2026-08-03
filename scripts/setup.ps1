# Runs the vendored installer and configures Cloudsmith CLI authentication
# for later workflow steps.
$ErrorActionPreference = "Stop"

$utf8NoBom = [Text.UTF8Encoding]::new($false)

function Add-GitHubLine {
  param([string]$Path, [string]$Line)
  [IO.File]::AppendAllText($Path, "$Line`n", $utf8NoBom)
}

# Values are written line-by-line, so a newline would inject extra variables.
function Write-JobEnvironment {
  param([string]$Name, [string]$Value)
  if ($Value.Contains("`n") -or $Value.Contains("`r")) {
    throw "$Name must not contain a newline"
  }
  Add-GitHubLine -Path $env:GITHUB_ENV -Line "$Name=$Value"
  Set-Item -Path "Env:$Name" -Value $Value
}

$hasApiKey = -not [string]::IsNullOrEmpty($env:INPUT_API_KEY)
$hasOidcNamespace = -not [string]::IsNullOrEmpty($env:INPUT_OIDC_NAMESPACE)
$hasOidcService = -not [string]::IsNullOrEmpty($env:INPUT_OIDC_SERVICE_SLUG)

if ($hasOidcNamespace -ne $hasOidcService) {
  throw "oidc-namespace and oidc-service-slug must be supplied together"
}

if (-not $hasApiKey -and -not $hasOidcNamespace) {
  throw "No authentication inputs were provided. Set 'api-key', or set 'oidc-namespace' and 'oidc-service-slug' (OIDC also requires the 'id-token: write' permission on the workflow or job)."
}

if (-not [string]::IsNullOrEmpty($env:INPUT_OIDC_AUDIENCE) -and -not $hasOidcNamespace) {
  throw "oidc-audience requires oidc-namespace and oidc-service-slug"
}

if ($hasOidcNamespace -and [string]::IsNullOrEmpty($env:ACTIONS_ID_TOKEN_REQUEST_URL)) {
  throw "OIDC authentication requires an ID token. Add 'permissions: id-token: write' to your workflow or job."
}

$apiSslVerify = ([string]$env:INPUT_API_SSL_VERIFY).ToLowerInvariant()
if ($apiSslVerify -notin @('', 'true', 'false')) {
  throw "api-ssl-verify must be true, false, or empty"
}

$verifyAuth = ([string]$env:INPUT_VERIFY_AUTH).ToLowerInvariant()
if ($verifyAuth -notin @('true', 'false')) {
  throw "verify-auth must be true or false"
}

$exportAuthToken = ([string]$env:INPUT_EXPORT_AUTH_TOKEN).ToLowerInvariant()
if ($exportAuthToken -notin @('true', 'false')) {
  throw "export-auth-token must be true or false"
}

$oidcAuthOnly = ([string]$env:INPUT_OIDC_AUTH_ONLY).ToLowerInvariant()
if ($oidcAuthOnly -notin @('true', 'false')) {
  throw "oidc-auth-only must be true or false"
}
if ($oidcAuthOnly -eq 'true') {
  Write-Host "::warning::The 'oidc-auth-only' input is deprecated; use 'export-auth-token'. Both resolve credentials through 'cloudsmith credential-helper generic'."
  $exportAuthToken = 'true'
}

$cliVersion = $env:INPUT_CLI_VERSION
if ([string]::IsNullOrWhiteSpace($cliVersion)) {
  $cliVersion = "latest"
}

$installRoot = [string]$env:INPUT_INSTALL_DIRECTORY
if ($installRoot.Contains("`n") -or $installRoot.Contains("`r")) {
  throw "install-directory must not contain a newline"
}
if ([string]::IsNullOrWhiteSpace($installRoot)) {
  $installRoot = Join-Path $env:RUNNER_TEMP "cloudsmith-cli"
}

$resultFile = Join-Path $env:RUNNER_TEMP ("cloudsmith-installer-result." + [Guid]::NewGuid().ToString("N"))
try {
  $installer = Join-Path $env:GITHUB_ACTION_PATH "installer\install.ps1"
  & $installer -Version $cliVersion -InstallRoot $installRoot -OutputFile $resultFile

  $result = @{}
  foreach ($line in [IO.File]::ReadAllLines($resultFile)) {
    if ($line -match '^([^=]+)=(.*)$') {
      $result[$matches[1]] = $matches[2]
    }
  }
}
finally {
  if (Test-Path -LiteralPath $resultFile) {
    Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
  }
}

foreach ($required in @('version', 'target', 'bin_dir', 'executable')) {
  if (-not $result.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($result[$required])) {
    throw "Installer did not return '$required'"
  }
}

$resolvedVersion = $result['version']
$target = $result['target']
$binDirectory = $result['bin_dir']
$executable = $result['executable']

# These values are written line-by-line to the GitHub command files.
foreach ($value in @($resolvedVersion, $target, $binDirectory, $executable)) {
  if ($value.Contains("`n") -or $value.Contains("`r")) {
    throw "Installer result must not contain a newline"
  }
}

if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
  throw "Cloudsmith executable was not installed at $executable"
}

Add-GitHubLine -Path $env:GITHUB_PATH -Line $binDirectory
$env:PATH = "$binDirectory;$env:PATH"

if ($hasApiKey) {
  if ($env:INPUT_API_KEY.Contains("`n") -or $env:INPUT_API_KEY.Contains("`r")) {
    throw "api-key must not contain a newline"
  }
  Write-Host "::add-mask::$($env:INPUT_API_KEY)"
  Write-JobEnvironment -Name CLOUDSMITH_API_KEY -Value $env:INPUT_API_KEY
}

if ($hasOidcNamespace) {
  $audience = $env:INPUT_OIDC_AUDIENCE
  if ([string]::IsNullOrEmpty($audience)) {
    # Keep the v2 default audience so existing Cloudsmith OIDC claim
    # mappings keep working after upgrading to v3.
    $audience = "https://github.com/$($env:GITHUB_REPOSITORY_OWNER)"
  }

  Write-JobEnvironment -Name CLOUDSMITH_ORG -Value $env:INPUT_OIDC_NAMESPACE
  Write-JobEnvironment -Name CLOUDSMITH_SERVICE_SLUG -Value $env:INPUT_OIDC_SERVICE_SLUG
  Write-JobEnvironment -Name CLOUDSMITH_OIDC_AUDIENCE -Value $audience
}

$apiHost = [string]$env:INPUT_API_HOST
if (-not [string]::IsNullOrEmpty($apiHost)) {
  if (-not $apiHost.Contains('://')) {
    # Match v2, which prefixed bare hosts with https://.
    $apiHost = "https://$apiHost"
  }
  Write-JobEnvironment -Name CLOUDSMITH_API_HOST -Value $apiHost
}
if (-not [string]::IsNullOrEmpty($env:INPUT_API_PROXY)) {
  Write-JobEnvironment -Name CLOUDSMITH_API_PROXY -Value $env:INPUT_API_PROXY
}
if (-not [string]::IsNullOrEmpty($env:INPUT_API_USER_AGENT)) {
  Write-JobEnvironment -Name CLOUDSMITH_API_USER_AGENT -Value $env:INPUT_API_USER_AGENT
}

switch ($apiSslVerify) {
  'true' { Write-JobEnvironment -Name CLOUDSMITH_WITHOUT_API_SSL_VERIFY -Value 'false' }
  'false' { Write-JobEnvironment -Name CLOUDSMITH_WITHOUT_API_SSL_VERIFY -Value 'true' }
}

$exportedToken = ''
$credentialUsername = ''
if ($exportAuthToken -eq 'true') {
  # Resolve once: the helper performs the OIDC exchange when OIDC is the
  # effective source and emits a versioned JSON credential document.
  $credentialJsonLines = & $executable credential-helper generic
  $credentialStatus = $LASTEXITCODE
  if ($credentialStatus -ne 0) {
    throw "Failed to resolve credentials. 'export-auth-token' requires Cloudsmith CLI 1.21.0 or later and valid credentials."
  }
  $credentialJson = ($credentialJsonLines | Out-String).Trim()
  if ([string]::IsNullOrEmpty($credentialJson)) {
    throw "The CLI returned an empty credential-helper response."
  }

  try {
    $credential = $credentialJson | ConvertFrom-Json -ErrorAction Stop
  }
  catch {
    throw "The CLI returned an invalid credential-helper response."
  }

  $properties = @($credential.PSObject.Properties.Name)
  $hasExpectedProperties = (
    $properties.Count -eq 3 -and
    $properties -contains 'version' -and
    $properties -contains 'username' -and
    $properties -contains 'password'
  )
  if (
    -not $hasExpectedProperties -or
    $credential.version -ne 1 -or
    $credential.username -ne 'token' -or
    $credential.password -isnot [string] -or
    [string]::IsNullOrEmpty($credential.password)
  ) {
    throw "The CLI returned an invalid or unsupported credential-helper response."
  }

  $credentialUsername = [string]$credential.username
  $exportedToken = [string]$credential.password
  if ($exportedToken.Contains("`n") -or $exportedToken.Contains("`r")) {
    throw "The CLI returned a token containing a newline"
  }
  Write-Host "::add-mask::$exportedToken"
  Write-JobEnvironment -Name CLOUDSMITH_API_KEY -Value $exportedToken
  Write-JobEnvironment -Name CLOUDSMITH_USERNAME -Value $credentialUsername
}

if ($verifyAuth -eq 'true') {
  # whoami prints its status to stdout. Some CLI builds exit 0 even on a 401,
  # so treat the failure marker in the output as authoritative too.
  $authOutput = & $executable whoami 2>&1
  $authStatus = $LASTEXITCODE
  $authOutput | ForEach-Object { Write-Output $_ }
  $authFailed = ($authOutput | Out-String) -match 'Failed to retrieve your authentication status'
  if ($authStatus -ne 0 -or $authFailed) {
    throw "Authentication verification failed. Check the credentials passed to this action."
  }
}

Add-GitHubLine -Path $env:GITHUB_OUTPUT -Line "cli-version=$resolvedVersion"
Add-GitHubLine -Path $env:GITHUB_OUTPUT -Line "target=$target"
Add-GitHubLine -Path $env:GITHUB_OUTPUT -Line "cli-path=$executable"
Add-GitHubLine -Path $env:GITHUB_OUTPUT -Line "bin-directory=$binDirectory"
if (-not [string]::IsNullOrEmpty($exportedToken)) {
  Add-GitHubLine -Path $env:GITHUB_OUTPUT -Line "oidc-token=$exportedToken"
}

Write-Host "Cloudsmith CLI $resolvedVersion is available at $executable"
