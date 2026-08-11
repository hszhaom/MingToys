$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $root "_data\breeds.yml"
$draftDirectory = Join-Path $root ".codex\drafts"

if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) {
  Write-Error "Ruby is required to parse the Jekyll breed catalog."
  exit 1
}

$catalogJson = & ruby -ryaml -rjson -e 'puts JSON.generate(YAML.load_file(ARGV[0]))' $catalogPath
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$draftKeys = @{}
Get-ChildItem -LiteralPath $draftDirectory -Filter '*.md' -File | ForEach-Object {
  if ($_.BaseName -match '^\d{4}-\d{2}-\d{2}-(.+)-breed-guide$') {
    $draftKeys[$Matches[1]] = $true
  }
}

$queue = foreach ($breed in ($catalogJson | ConvertFrom-Json)) {
  if ($breed.publication_status -eq 'planned' -and -not $draftKeys.ContainsKey($breed.key.ToString())) {
    [pscustomobject]@{
      key = $breed.key
      name = $breed.name
      group = $breed.group
      origin = $breed.origin
      breed_standard_url = $breed.breed_standard_url
      url = $breed.url
    }
  }
}

$queue | Sort-Object group, name
