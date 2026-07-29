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

Write-Host "Content quality checks passed for $($monetized.Count) monetized pages and posts."
