$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$draftDirectory = Join-Path $root ".codex\drafts"
$issues = New-Object System.Collections.Generic.List[string]

function Get-BodyWordCount {
  param([string]$Raw)

  $body = [regex]::Replace($Raw, '(?s)\A---\s*.*?\s*---\s*', '')
  $plain = [regex]::Replace($body, '(?s)\{\{.*?\}\}|<[^>]+>|!?\[[^\]]*\]\([^\)]*\)|[#|>*_`~-]', ' ')
  return [regex]::Matches($plain, "[A-Za-z]+(?:['-][A-Za-z]+)*").Count
}

function Get-InternalContentLinks {
  param([string]$Raw)

  $excluded = @(
    '/dog-cost-calculator/',
    '/dog-fit-score-cards/',
    '/about/',
    '/contact/',
    '/editorial-policy/',
    '/data-sources/'
  )

  return @(
    [regex]::Matches($Raw, '\]\(\{\{\s*site\.url\s*\}\}(/[^\s\)]+)') |
      ForEach-Object { $_.Groups[1].Value } |
      Where-Object { $_ -notin $excluded } |
      Select-Object -Unique
  )
}

function Get-CustomDecisionHeadings {
  param([string]$Raw)

  $standardHeadingPattern = '(?i)(Quick Facts|Temperament|Common .+ Health Issues|Pros and Cons|Is .+ Right for You\?|FAQ)$'
  return @(
    [regex]::Matches($Raw, '(?m)^##\s+(.+?)\s*$') |
      ForEach-Object { $_.Groups[1].Value.Trim() } |
      Where-Object { $_ -notmatch $standardHeadingPattern }
  )
}

if (-not (Test-Path -LiteralPath $draftDirectory)) {
  Write-Host "No local breed-guide drafts found."
  exit 0
}

if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) {
  Write-Error "Ruby is required to validate the Jekyll breed catalog."
  exit 1
}

$catalogPath = Join-Path $root "_data\breeds.yml"
$catalogJson = & ruby -ryaml -rjson -e 'puts JSON.generate(YAML.load_file(ARGV[0]))' $catalogPath
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($catalogJson)) {
  Write-Error "Could not parse _data/breeds.yml as YAML."
  exit 1
}

$catalog = $catalogJson | ConvertFrom-Json
$openingSignatures = @{}
$drafts = Get-ChildItem -LiteralPath $draftDirectory -Filter '*.md' -File
$publishedPostUrls = @{}

Get-ChildItem -LiteralPath (Join-Path $root '_posts') -Filter '*.md' -File | ForEach-Object {
  if ($_.BaseName -match '^(\d{4})-(\d{2})-(\d{2})-(.+)$') {
    $publishedPostUrls["/posts/$($Matches[1])/$($Matches[2])/$($Matches[3])/$($Matches[4])/"] = $true
  }
}

foreach ($draft in $drafts) {
  $raw = [System.IO.File]::ReadAllText($draft.FullName)
  $name = $draft.Name

  foreach ($required in @(
    '(?m)^layout:\s*post\s*$',
    '(?m)^adsense:\s*false\s*$',
    '(?m)^noindex:\s*true\s*$',
    '(?m)^sitemap:\s*false\s*$',
    '(?m)^updated:\s*["'']?\d{4}-\d{2}-\d{2}["'']?\s*$'
  )) {
    if ($raw -notmatch $required) {
      $issues.Add("$name is missing required review-only front matter: $required")
    }
  }

  $slugMatch = [regex]::Match($name, '^\d{4}-\d{2}-\d{2}-(.+)-breed-guide\.md$')
  if (-not $slugMatch.Success) {
    $issues.Add("$name does not follow the expected draft file name pattern.")
    continue
  }

  $slug = $slugMatch.Groups[1].Value
  $breed = @($catalog | Where-Object { $_.key -eq $slug })
  if ($breed.Count -ne 1) {
    $issues.Add("$name does not map to exactly one breed catalog key.")
  } else {
    if ($breed[0].publication_status -ne 'planned') {
      $issues.Add("$name belongs to '$slug', which must remain planned until images and editorial review are complete.")
    }
    foreach ($field in @('summary', 'size', 'home', 'experience', 'kids', 'exercise', 'shedding', 'grooming', 'training', 'health_risk', 'cost_level', 'caution')) {
      if ([string]$breed[0].$field -eq 'pending') {
        $issues.Add("$name maps to '$slug' with pending catalog field '$field'.")
      }
    }
  }

  $sourceCount = [regex]::Matches($raw, '(?m)^  - organization:').Count
  $faqQuestions = [regex]::Matches($raw, '(?m)^  - question:').Count
  $faqAnswers = [regex]::Matches($raw, '(?m)^    answer:').Count
  $wordCount = Get-BodyWordCount $raw
  $decisionHeadings = Get-CustomDecisionHeadings $raw
  $internalLinks = Get-InternalContentLinks $raw

  if ($sourceCount -lt 3) { $issues.Add("$name has only $sourceCount sources; expected at least 3.") }
  if ($faqQuestions -lt 3 -or $faqQuestions -ne $faqAnswers) { $issues.Add("$name has inconsistent faq_schema data.") }
  if ($wordCount -lt 900) { $issues.Add("$name has $wordCount effective English words; expected at least 900.") }
  if ($decisionHeadings.Count -lt 3) { $issues.Add("$name has only $($decisionHeadings.Count) breed-specific decision sections; expected at least 3.") }
  if ($internalLinks.Count -lt 2) { $issues.Add("$name has only $($internalLinks.Count) related internal content links; expected at least 2.") }
  foreach ($internalLink in $internalLinks | Where-Object { $_ -like '/posts/*' }) {
    if (-not $publishedPostUrls.ContainsKey($internalLink)) {
      $issues.Add("$name links to unpublished or missing article $internalLink.")
    }
  }
  if ($raw -notmatch '/dog-cost-calculator/' -or $raw -notmatch '/dog-fit-score-cards/') { $issues.Add("$name must link directly to both dog decision tools.") }
  if ($raw -match '(?i)\b(based on (?:interviews|conversations)|interviewed|we spoke (?:with|to)|we asked)\b') { $issues.Add("$name contains an unsupported interview claim.") }
  if ($raw -match '(?i)\bthe overlooked\b') { $issues.Add("$name contains the repeated AI-style phrase 'the overlooked'.") }
  if ($raw.Contains([char]0xFFFD)) { $issues.Add("$name contains a Unicode replacement character.") }

  $body = [regex]::Replace($raw, '(?s)\A---\s*.*?\s*---\s*', '').Trim()
  $opening = ([regex]::Split($body, '\r?\n\s*\r?\n') | Where-Object {
    ([regex]::Matches($_, "[A-Za-z]+(?:['-][A-Za-z]+)*").Count -ge 12)
  } | Select-Object -First 1)
  if (-not [string]::IsNullOrWhiteSpace($opening)) {
    $signature = (([regex]::Matches($opening, "[A-Za-z]+(?:['-][A-Za-z]+)*") | Select-Object -First 24 | ForEach-Object { $_.Value.ToLowerInvariant() }) -join ' ')
    if ($openingSignatures.ContainsKey($signature)) {
      $issues.Add("$name repeats the opening used by $($openingSignatures[$signature]).")
    } else {
      $openingSignatures[$signature] = $name
    }
  }
}

if ($issues.Count -gt 0) {
  $issues | ForEach-Object { Write-Host "ERROR: $_" }
  exit 1
}

Write-Host "Draft breed-guide checks passed for $($drafts.Count) review-only drafts."
