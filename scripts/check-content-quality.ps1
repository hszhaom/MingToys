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

$guidancePath = Join-Path $root '_data\breed_owner_guidance.json'
$guidanceRaw = [System.IO.File]::ReadAllText($guidancePath)
$guidanceData = $guidanceRaw | ConvertFrom-Json
$guidanceEntries = @($guidanceData.PSObject.Properties)
$requiredGuidanceFields = @(
  'breed',
  'updated',
  'owner_heading',
  'owner_note',
  'scenario_heading',
  'apartment_label',
  'apartment',
  'house_label',
  'house',
  'first_time_label',
  'first_time',
  'experienced_label',
  'experienced',
  'myths_heading',
  'tools_heading',
  'tool_intro',
  'cost_use',
  'fit_use'
)
$guidanceParagraphOwners = @{}
$guidanceHeadingOwners = @{}

foreach ($entry in $guidanceEntries) {
  foreach ($field in $requiredGuidanceFields) {
    if ([string]::IsNullOrWhiteSpace([string]$entry.Value.$field)) {
      $issues.Add("$($entry.Name) is missing owner-guidance field $field.")
    }
  }

  if ([string]$entry.Value.updated -notmatch '^\d{4}-\d{2}-\d{2}$') {
    $issues.Add("$($entry.Name) has an invalid owner-guidance updated date.")
  }

  $myths = @($entry.Value.myths)
  if ($myths.Count -lt 2 -or $myths.Count -gt 3) {
    $issues.Add("$($entry.Name) must have 2 or 3 breed misconceptions.")
  }

  $guidanceText = @(
    $entry.Value.owner_note,
    $entry.Value.apartment,
    $entry.Value.house,
    $entry.Value.first_time,
    $entry.Value.experienced,
    $entry.Value.tool_intro,
    $entry.Value.cost_use,
    $entry.Value.fit_use
  )
  foreach ($myth in $myths) {
    if ([string]::IsNullOrWhiteSpace([string]$myth.claim) -or [string]::IsNullOrWhiteSpace([string]$myth.correction)) {
      $issues.Add("$($entry.Name) has an incomplete breed misconception.")
    }
    $guidanceText += $myth.claim
    $guidanceText += $myth.correction
  }

  $guidanceWordCount = [regex]::Matches(($guidanceText -join ' '), "[A-Za-z]+(?:['-][A-Za-z]+)*").Count
  if ($guidanceWordCount -lt 250) {
    $issues.Add("$($entry.Name) adds only $guidanceWordCount owner-guidance words; expected at least 250.")
  }

  foreach ($paragraph in $guidanceText) {
    $normalized = ([regex]::Replace($paragraph.ToLowerInvariant(), '\s+', ' ')).Trim()
    if ($guidanceParagraphOwners.ContainsKey($normalized)) {
      $issues.Add("$($entry.Name) duplicates owner-guidance text from $($guidanceParagraphOwners[$normalized]).")
    } else {
      $guidanceParagraphOwners[$normalized] = $entry.Name
    }
  }

  foreach ($heading in @(
    $entry.Value.owner_heading,
    $entry.Value.scenario_heading,
    $entry.Value.apartment_label,
    $entry.Value.house_label,
    $entry.Value.first_time_label,
    $entry.Value.experienced_label,
    $entry.Value.myths_heading,
    $entry.Value.tools_heading
  )) {
    $normalized = $heading.ToLowerInvariant().Trim()
    if ($guidanceHeadingOwners.ContainsKey($normalized)) {
      $issues.Add("$($entry.Name) duplicates an owner-guidance heading from $($guidanceHeadingOwners[$normalized]).")
    } else {
      $guidanceHeadingOwners[$normalized] = $entry.Name
    }
  }
}

$postSlugs = Get-ChildItem (Join-Path $root '_posts') -Filter '*.md' | ForEach-Object {
  $_.BaseName -replace '^\d{4}-\d{2}-\d{2}-', ''
}
$guidanceSlugs = @($guidanceEntries.Name)
foreach ($slug in $postSlugs) {
  if ($slug -notin $guidanceSlugs) { $issues.Add("Post $slug has no owner-guidance data.") }
}
foreach ($slug in $guidanceSlugs) {
  if ($slug -notin $postSlugs) { $issues.Add("Owner-guidance data $slug has no matching post.") }
}

if ($guidanceRaw -match '(?i)interview(?:ed|s)?\s+(?:with\s+)?(?:20|twenty)') {
  $issues.Add('Owner-guidance data contains an unsupported interview claim.')
}
if ($guidanceRaw -match '(?i)\bthe overlooked\b') {
  $issues.Add('Owner-guidance data contains the repeated AI-style phrase "the overlooked".')
}

$guidanceInclude = [System.IO.File]::ReadAllText((Join-Path $root '_includes\breed-owner-guidance.html'))
if ($guidanceInclude -notmatch '/dog-cost-calculator/' -or $guidanceInclude -notmatch '/dog-fit-score-cards/') {
  $issues.Add('Owner-guidance modules must link to both dog decision tools.')
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

Write-Host "Content quality checks passed for $($monetized.Count) monetized pages and $($guidanceEntries.Count) owner-guidance entries."
