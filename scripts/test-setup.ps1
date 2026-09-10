$ErrorActionPreference = 'Stop'
$setupScript = Join-Path $PSScriptRoot 'setup.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("cloudsmith-setup-test-" + [Guid]::NewGuid().ToString('N'))

function Assert-Equal {
  param($Actual, $Expected)
  if ($Actual -cne $Expected) {
    throw "Expected '$Expected', got '$Actual'"
  }
}

function Invoke-SetupTest {
  param([string]$Expected)
  Set-Content -LiteralPath $env:GITHUB_ENV -Value ''
  Set-Content -LiteralPath $env:GITHUB_OUTPUT -Value ''
  # Use a fresh process, just like a separate action step.
  & (Join-Path $PSHOME 'pwsh') -NoProfile -File $setupScript
  Assert-Equal $LASTEXITCODE 0
  foreach ($line in Get-Content -LiteralPath $env:GITHUB_ENV) {
    if ($line -match '^([^=]+)=(.*)$') {
      Set-Item -Path "Env:$($matches[1])" -Value $matches[2]
    }
  }
  Assert-Equal $env:CLOUDSMITH_API_KEY $Expected
  Assert-Equal (Get-Content (Join-Path $testRoot 'verified.log') | Select-Object -Last 1) $Expected
  Assert-Equal ((Get-Content $env:GITHUB_ENV) -contains "CLOUDSMITH_API_KEY=$Expected") $true
  if ($env:INPUT_EXPORT_AUTH_TOKEN -eq 'true' -or $env:INPUT_OIDC_AUTH_ONLY -eq 'true') {
    Assert-Equal $env:CLOUDSMITH_USERNAME 'token'
    Assert-Equal ((Get-Content $env:GITHUB_OUTPUT) -contains "oidc-token=$Expected") $true
  }
}

try {
  New-Item -ItemType Directory -Path "$testRoot/installer", "$testRoot/bin" | Out-Null
  @'
param($Version, $InstallRoot, $OutputFile)
$binDirectory = Join-Path $env:GITHUB_ACTION_PATH 'bin'
$executable = Join-Path $binDirectory 'cloudsmith.ps1'
Set-Content -LiteralPath $OutputFile -Value @(
  'version=1.21.0', 'target=test', "bin_dir=$binDirectory", "executable=$executable"
)
'@ | Set-Content -LiteralPath "$testRoot/installer/install.ps1"
  @'
$global:LASTEXITCODE = 0
switch ($args -join ' ') {
  'credential-helper generic' {
    Add-Content "$env:GITHUB_ACTION_PATH/helper.log" 'helper'
    # Match CLI precedence: an API key wins over OIDC.
    $token = $env:CLOUDSMITH_API_KEY
    if ([string]::IsNullOrEmpty($token)) {
      Add-Content "$env:GITHUB_ACTION_PATH/exchanges.log" $env:CLOUDSMITH_SERVICE_SLUG
      $token = "token-$env:CLOUDSMITH_SERVICE_SLUG"
    }
    @{ version = 1; username = 'token'; password = $token } | ConvertTo-Json -Compress
  }
  'whoami' { Add-Content "$env:GITHUB_ACTION_PATH/verified.log" $env:CLOUDSMITH_API_KEY }
  default { throw "Unexpected CLI arguments: $args" }
}
'@ | Set-Content -LiteralPath "$testRoot/bin/cloudsmith.ps1"

  $env:GITHUB_ACTION_PATH = $testRoot
  $env:RUNNER_TEMP = $testRoot
  $env:GITHUB_ENV = Join-Path $testRoot 'env'
  $env:GITHUB_OUTPUT = Join-Path $testRoot 'output'
  $env:GITHUB_PATH = Join-Path $testRoot 'path'
  $env:GITHUB_REPOSITORY_OWNER = 'test-owner'
  $env:ACTIONS_ID_TOKEN_REQUEST_URL = 'https://example.invalid/oidc'
  $env:INPUT_CLI_VERSION = 'latest'
  $env:INPUT_INSTALL_DIRECTORY = ''
  $env:INPUT_API_KEY = ''
  $env:INPUT_OIDC_NAMESPACE = 'test-org'
  $env:INPUT_OIDC_SERVICE_SLUG = 'pull-only'
  $env:INPUT_OIDC_AUDIENCE = ''
  $env:INPUT_API_HOST = ''
  $env:INPUT_API_PROXY = ''
  $env:INPUT_API_SSL_VERIFY = ''
  $env:INPUT_API_USER_AGENT = ''
  $env:INPUT_VERIFY_AUTH = 'true'
  $env:INPUT_EXPORT_AUTH_TOKEN = 'true'
  $env:INPUT_OIDC_AUTH_ONLY = 'false'
  $env:CLOUDSMITH_API_KEY = $null

  Invoke-SetupTest 'token-pull-only'
  $env:INPUT_OIDC_SERVICE_SLUG = 'push-capable'
  Invoke-SetupTest 'token-push-capable'
  Assert-Equal ((Get-Content "$testRoot/exchanges.log") -join ',') 'pull-only,push-capable'
  Assert-Equal @(Get-Content "$testRoot/helper.log").Count 2

  # Explicit API keys still win, even with OIDC inputs and an inherited token.
  $env:INPUT_API_KEY = 'explicit-key'
  Invoke-SetupTest 'explicit-key'
  $env:INPUT_OIDC_NAMESPACE = ''
  $env:INPUT_OIDC_SERVICE_SLUG = ''
  $env:INPUT_API_KEY = 'api-only-key'
  Invoke-SetupTest 'api-only-key'
  Assert-Equal ((Get-Content "$testRoot/exchanges.log") -join ',') 'pull-only,push-capable'
  Assert-Equal @(Get-Content "$testRoot/helper.log").Count 4

  $env:INPUT_EXPORT_AUTH_TOKEN = 'false'
  $env:INPUT_API_KEY = 'unexported-key'
  Invoke-SetupTest 'unexported-key'
  Assert-Equal @(Get-Content "$testRoot/helper.log").Count 4
  Assert-Equal ([bool]((Get-Content $env:GITHUB_OUTPUT) -match '^oidc-token=')) $false

  # The deprecated alias must also ignore the previously exported API key.
  $env:INPUT_API_KEY = ''
  $env:INPUT_OIDC_NAMESPACE = 'test-org'
  $env:INPUT_OIDC_SERVICE_SLUG = 'alias-service'
  $env:INPUT_OIDC_AUTH_ONLY = 'true'
  Invoke-SetupTest 'token-alias-service'
  Assert-Equal ((Get-Content "$testRoot/exchanges.log") -join ',') 'pull-only,push-capable,alias-service'
  Write-Output 'PowerShell setup tests passed'
}
finally {
  if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}
