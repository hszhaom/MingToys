$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "check-content-quality.ps1")
if (-not $?) {
  exit 1
}

& (Join-Path $PSScriptRoot "check-draft-breed-guides.ps1")
if (-not $?) {
  exit 1
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host "Node.js is not installed. Install Node.js before checking interactive tools."
  exit 1
}

node (Join-Path $PSScriptRoot "check-cost-calculator.js")
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) {
  Write-Host "Ruby is not installed. Install Ruby before running a local Jekyll build."
  exit 1
}

if (-not (Get-Command bundle -ErrorAction SilentlyContinue)) {
  Write-Host "Bundler is not installed. Run: gem install bundler"
  exit 1
}

bundle check
if ($LASTEXITCODE -ne 0) {
  Write-Host "Jekyll dependencies are missing. Run: bundle install"
  exit $LASTEXITCODE
}

if (-not (Get-Command jekyll -ErrorAction SilentlyContinue)) {
  Write-Host "The Jekyll executable is missing. Run: bundle install"
  exit 1
}

jekyll build
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

node (Join-Path $PSScriptRoot "check-built-site.js")
exit $LASTEXITCODE
