$ErrorActionPreference = "Stop"

if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) {
  Write-Host "Ruby is not installed. Install Ruby before running a local Jekyll build."
  exit 1
}

if (-not (Get-Command bundle -ErrorAction SilentlyContinue)) {
  Write-Host "Bundler is not installed. Run: gem install bundler"
  exit 1
}

bundle exec jekyll build
