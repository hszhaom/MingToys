$ErrorActionPreference = "Stop"

$issues = New-Object System.Collections.Generic.List[string]
$root = Split-Path -Parent $PSScriptRoot

function Get-BodyWordCount {
  param([string]$Raw, [string]$Extension)

  $body = [regex]::Replace($Raw, '(?s)\A---\s*.*?\s*---\s*', '')
  if ($Extension -eq '.html') {
    $body = [regex]::Replace($body, '(?s)<script.*?</script>|<style.*?</style>', ' ')
    $plain = [regex]::Replace($body, '(?s)\{\%.*?\%\}|\{\{.*?\}\}|<[^>]+>|&[A-Za-z#0-9]+;', ' ')
  } else {
    $plain = [regex]::Replace($body, '(?s)\{\{.*?\}\}|<[^>]+>|!?\[[^\]]*\]\([^\)]*\)|[#|>*_`~-]', ' ')
  }
  return [regex]::Matches($plain, "[A-Za-z]+(?:['-][A-Za-z]+)*").Count
}

$adsenseInclude = [System.IO.File]::ReadAllText((Join-Path $root '_includes\adsense.html'))
if ($adsenseInclude -match 'page\.layout\s*==\s*["'']post') {
  $issues.Add('AdSense still loads automatically for every post layout.')
}

$monetized = Get-ChildItem (Join-Path $root '_posts'), (Join-Path $root 'pages') -File -Recurse | Where-Object {
  [System.IO.File]::ReadAllText($_.FullName) -match '(?m)^adsense:\s*true\s*$'
}

foreach ($file in $monetized) {
  $raw = [System.IO.File]::ReadAllText($file.FullName)
  $sourceCount = [regex]::Matches($raw, '(?m)^  - organization:').Count
  $faqCount = [regex]::Matches($raw, '(?m)^  - question:').Count
  $wordCount = Get-BodyWordCount $raw $file.Extension
  $minimumWords = if ($file.Directory.Name -eq 'pages') { 1000 } else { 900 }

  if ($sourceCount -lt 3) { $issues.Add("$($file.Name) has only $sourceCount sources.") }
  if ($faqCount -lt 3) { $issues.Add("$($file.Name) has only $faqCount FAQ items.") }
  if ($wordCount -lt $minimumWords) { $issues.Add("$($file.Name) has $wordCount words; expected at least $minimumWords.") }

  if ($file.Directory.Name -eq '_posts') {
    $legacyHeadingPattern = '(?m)^## (Real-Life Fit Score|Exercise Needs|Grooming and Shedding|Feeding and Weight Control|Training Tips|Final Verdict|Space, Cost, and Family Q&A)\s*$'
    $legacyPhrasePattern = '(?i)\b(The first 30 days|The common mistake)\b'
    $headings = [regex]::Matches($raw, '(?m)^##\s+(.+?)\s*$') | ForEach-Object {
      $_.Groups[1].Value.Trim()
    }
    $decisionHeadings = $headings | Where-Object {
      $_ -notmatch '(?i)(Quick Facts|Temperament|Common .+ Health Issues|Pros and Cons|Is .+ Right for You\?|FAQ)$'
    }

    if ($raw -match $legacyHeadingPattern) {
      $issues.Add("$($file.Name) has a legacy shared-template heading: $($Matches[1]).")
    }
    if ($raw -match $legacyPhrasePattern) {
      $issues.Add("$($file.Name) has a legacy shared-template phrase: $($Matches[1]).")
    }
    if ($decisionHeadings.Count -lt 3) {
      $issues.Add("$($file.Name) has only $($decisionHeadings.Count) breed-specific decision sections; expected at least 3.")
    }
  }
}

$requiredTopicPages = @(
  'calm-dog-breeds-for-busy-owners.html',
  'best-dogs-for-first-time-owners.html',
  'low-shedding-dog-breeds.html',
  'apartment-dog-breeds.html',
  'small-dog-breeds.html',
  'best-family-dogs.html'
)

foreach ($name in $requiredTopicPages) {
  $path = Join-Path $root "pages\$name"
  $raw = [System.IO.File]::ReadAllText($path)
  $wordCount = Get-BodyWordCount $raw '.html'
  if ($raw -notmatch '(?m)^adsense:\s*false\s*$') { $issues.Add("$name must keep AdSense disabled.") }
  if ($wordCount -lt 900) { $issues.Add("$name has $wordCount words; expected at least 900.") }
}

$sitemap = [System.IO.File]::ReadAllText((Join-Path $root 'sitemap.xml'))
if ($sitemap -match 'site\.time') { $issues.Add('sitemap.xml still uses site.time for lastmod.') }

$firstStory = [System.IO.File]::ReadAllText((Join-Path $root '_posts\2026-05-28-first-story.md'))
if ($firstStory -match '(?m)^sitemap:\s*false\s*$') { $issues.Add('The Corgi comparison is still excluded from the sitemap.') }

$fitCards = [System.IO.File]::ReadAllText((Join-Path $root 'pages\dog-fit-score-cards.html'))
$nonDiscreteWidths = [regex]::Matches($fitCards, 'style="width:\s*(\d+)%"') | Where-Object {
  ([int]$_.Groups[1].Value % 20) -ne 0
}
if ($nonDiscreteWidths.Count -gt 0) { $issues.Add('Fit Score Cards still contain non-discrete percentage widths.') }

$postFiles = Get-ChildItem (Join-Path $root '_posts') -Filter '*.md'
$legacyHeadingPattern = '(?m)^## (Real-Life Fit Score|Exercise Needs|Grooming and Shedding|Feeding and Weight Control|Training Tips|Final Verdict|Space, Cost, and Family Q&A)\s*$'
$unsupportedInterviewPattern = '(?i)\b(based on (?:interviews|conversations)|interviewed|we spoke (?:with|to)|we asked)\b'

foreach ($file in $postFiles) {
  $raw = [System.IO.File]::ReadAllText($file.FullName)
  $headings = [regex]::Matches($raw, '(?m)^##\s+(.+?)\s*$') | ForEach-Object {
    $_.Groups[1].Value.Trim()
  }
  $decisionHeadings = $headings | Where-Object {
    $_ -notmatch '(?i)(Quick Facts|Temperament|Common .+ Health Issues|Pros and Cons|Is .+ Right for You\?|FAQ)$'
  }

  if ($raw -match $legacyHeadingPattern) {
    $issues.Add("$($file.Name) has a legacy shared-template heading: $($Matches[1]).")
  }
  if ($decisionHeadings.Count -lt 3) {
    $issues.Add("$($file.Name) has only $($decisionHeadings.Count) breed-specific decision sections; expected at least 3.")
  }
  if ($raw -notmatch '/dog-cost-calculator/' -or $raw -notmatch '/dog-fit-score-cards/') {
    $issues.Add("$($file.Name) must link directly to both dog decision tools.")
  }
  if ($raw -notmatch '(?m)^updated:\s*["'']?\d{4}-\d{2}-\d{2}["'']?\s*$') {
    $issues.Add("$($file.Name) is missing a page-level updated date.")
  }
  if ($raw -match $unsupportedInterviewPattern) {
    $issues.Add("$($file.Name) contains an unsupported interview claim.")
  }
  if ($raw -match '(?i)\bthe overlooked\b') {
    $issues.Add("$($file.Name) contains the repeated AI-style phrase 'the overlooked'.")
  }

  $hasSources = $raw -match '(?m)^sources:\s*$'
  $hasAds = $raw -match '(?m)^adsense:\s*true\s*$'
  if (-not $hasSources -and $raw -notmatch '(?m)^adsense:\s*false\s*$') {
    $issues.Add("$($file.Name) has no sources and must keep AdSense disabled.")
  }
  if ($hasAds -and -not $hasSources) {
    $issues.Add("$($file.Name) enables AdSense without page-level sources.")
  }
}

$retiredGuidancePath = Join-Path $root '_data\breed_owner_guidance.json'
if (Test-Path -LiteralPath $retiredGuidancePath) {
  $issues.Add('The retired owner-guidance data file is still present.')
}
$retiredGuidanceInclude = Join-Path $root '_includes\breed-owner-guidance.html'
if (Test-Path -LiteralPath $retiredGuidanceInclude) {
  $issues.Add('The retired owner-guidance include is still present.')
}
if ([System.IO.File]::ReadAllText((Join-Path $root '_layouts\post.html')) -match 'breed-owner-guidance|breed_owner_guidance') {
  $issues.Add('Post layout still renders centralized owner guidance.')
}

$imageRefs = foreach ($file in Get-ChildItem (Join-Path $root '_posts'), (Join-Path $root 'pages') -File -Recurse) {
  $raw = [System.IO.File]::ReadAllText($file.FullName)
  foreach ($match in [regex]::Matches($raw, '/assets/images/[A-Za-z0-9._-]+')) {
    [pscustomobject]@{ File = $file.Name; Reference = $match.Value }
  }
}
foreach ($imageRef in $imageRefs) {
  $assetPath = Join-Path $root $imageRef.Reference.TrimStart('/').Replace('/', '\')
  if (-not (Test-Path -LiteralPath $assetPath)) {
    $issues.Add("$($imageRef.File) references missing image $($imageRef.Reference).")
  }
}

$breedImageHashes = Get-ChildItem (Join-Path $root 'assets\images') -File | Where-Object {
  $_.Name -match '-(cover|main|play)\.jpg$'
} | ForEach-Object {
  [pscustomobject]@{
    Name = $_.Name
    Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
  }
}

$breedImageHashes | Group-Object Hash | Where-Object { $_.Count -gt 1 } | ForEach-Object {
  $duplicates = ($_.Group.Name | Sort-Object) -join ', '
  $issues.Add("Breed image files contain identical pixels: $duplicates.")
}

if ($issues.Count -gt 0) {
  $issues | ForEach-Object { Write-Error $_ }
  exit 1
}

Write-Host "Content quality checks passed for $($monetized.Count) monetized pages and $($postFiles.Count) directly maintained articles."
