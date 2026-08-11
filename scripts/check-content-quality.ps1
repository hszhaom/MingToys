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

function Get-FirstBodyParagraph {
  param([string]$Raw)

  $body = [regex]::Replace($Raw, '(?s)\A---\s*.*?\s*---\s*', '').Trim()
  foreach ($block in [regex]::Split($body, '\r?\n\s*\r?\n')) {
    $plain = [regex]::Replace($block, '(?m)^#{1,6}\s+.*$|!\[[^\]]*\]\([^\)]*\)|\|.*\||\{\{.*?\}\}', ' ')
    $words = [regex]::Matches($plain, "[A-Za-z]+(?:['-][A-Za-z]+)*")
    if ($words.Count -ge 12) {
      return (($words | Select-Object -First 24 | ForEach-Object { $_.Value.ToLowerInvariant() }) -join ' ')
    }
  }

  return $null
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

$adsenseInclude = [System.IO.File]::ReadAllText((Join-Path $root '_includes\adsense.html'))
if ($adsenseInclude -match 'page\.layout\s*==\s*["'']post') {
  $issues.Add('AdSense still loads automatically for every post layout.')
}
if ($adsenseInclude -notmatch 'site\.adsense_enabled') {
  $issues.Add('AdSense include is missing the site-wide pause switch.')
}

$faqInclude = [System.IO.File]::ReadAllText((Join-Path $root '_includes\faq.html'))
$defaultLayout = [System.IO.File]::ReadAllText((Join-Path $root '_layouts\default.html'))
if ($faqInclude -notmatch 'page\.faq_schema') {
  $issues.Add('Visible FAQs must render from page.faq_schema.')
}
if ($defaultLayout -notmatch '"@type": "FAQPage"' -or $defaultLayout -notmatch 'page\.faq_schema') {
  $issues.Add('FAQ JSON-LD must render from the same page.faq_schema data as visible FAQs.')
}

$adEligible = Get-ChildItem (Join-Path $root '_posts'), (Join-Path $root 'pages') -File -Recurse | Where-Object {
  [System.IO.File]::ReadAllText($_.FullName) -match '(?m)^adsense:\s*true\s*$'
}

$sourceReviewedPosts = @(
  Get-ChildItem (Join-Path $root '_posts') -Filter '*.md' | Where-Object {
    $raw = [System.IO.File]::ReadAllText($_.FullName)
    $raw -match '(?m)^sources:\s*$'
  }
)

$openingSignatures = @{}
foreach ($file in $sourceReviewedPosts) {
  $raw = [System.IO.File]::ReadAllText($file.FullName)
  $opening = Get-FirstBodyParagraph $raw
  if ([string]::IsNullOrWhiteSpace($opening)) {
    $issues.Add("$($file.Name) has no usable opening paragraph.")
  } elseif ($openingSignatures.ContainsKey($opening)) {
    $issues.Add("$($file.Name) repeats the opening used by $($openingSignatures[$opening]).")
  } else {
    $openingSignatures[$opening] = $file.Name
  }

  $headings = @([regex]::Matches($raw, '(?m)^##\s+(.+?)\s*$') | ForEach-Object { $_.Groups[1].Value.Trim() })
  $duplicateHeadings = $headings | Group-Object { $_.ToLowerInvariant() } | Where-Object { $_.Count -gt 1 }
  foreach ($duplicate in $duplicateHeadings) {
    $issues.Add("$($file.Name) repeats H2 heading '$($duplicate.Group[0])'.")
  }

  $customHeadings = Get-CustomDecisionHeadings $raw
  if ($customHeadings.Count -lt 3) {
    $issues.Add("$($file.Name) has only $($customHeadings.Count) breed-specific decision sections; expected at least 3.")
  }

  $internalContentLinks = Get-InternalContentLinks $raw
  if ($internalContentLinks.Count -lt 2) {
    $issues.Add("$($file.Name) has only $($internalContentLinks.Count) related internal content links; expected at least 2.")
  }

  $faqQuestions = [regex]::Matches($raw, '(?m)^  - question:\s*').Count
  $faqAnswers = [regex]::Matches($raw, '(?m)^    answer:\s*').Count
  if ($faqQuestions -lt 3 -or $faqQuestions -ne $faqAnswers) {
    $issues.Add("$($file.Name) has inconsistent faq_schema question/answer data.")
  }
  if ($raw -match '(?m)^##\s+FAQ\s*$') {
    $issues.Add("$($file.Name) duplicates FAQ content outside faq_schema.")
  }

  $stockPhrases = @(
    @{ Label = 'not just'; Pattern = '(?i)\bnot just\b'; Maximum = 2 },
    @{ Label = 'rather than'; Pattern = '(?i)\brather than\b'; Maximum = 8 },
    @{ Label = 'the reality is'; Pattern = '(?i)\bthe reality is\b'; Maximum = 1 },
    @{ Label = 'when it comes to'; Pattern = '(?i)\bwhen it comes to\b'; Maximum = 1 },
    @{ Label = 'it is important to'; Pattern = '(?i)\bit is important to\b'; Maximum = 1 },
    @{ Label = 'ordinary week'; Pattern = '(?i)\ban ordinary week\b'; Maximum = 0 }
  )
  foreach ($phrase in $stockPhrases) {
    $count = [regex]::Matches($raw, $phrase.Pattern).Count
    if ($count -gt $phrase.Maximum) {
      $issues.Add("$($file.Name) uses '$($phrase.Label)' $count times; maximum is $($phrase.Maximum).")
    }
  }
}

foreach ($file in $adEligible) {
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
    $decisionHeadings = Get-CustomDecisionHeadings $raw

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

$requiredEditorialPages = @(
  'calm-dog-breeds-for-busy-owners.html',
  'best-dogs-for-first-time-owners.html',
  'low-shedding-dog-breeds.html',
  'apartment-dog-breeds.html',
  'small-dog-breeds.html',
  'best-family-dogs.html',
  'dog-breeds.html',
  'dog-breed-comparisons.html',
  'which-dog-should-i-get.html',
  'high-energy-working-dogs.html',
  'large-dog-breeds.html',
  'guardian-dog-breeds-compared.html',
  'dog-cost-calculator.html',
  'training-behavior.html',
  'home-routines.html'
)

foreach ($name in $requiredEditorialPages) {
  $path = Join-Path $root "pages\$name"
  $raw = [System.IO.File]::ReadAllText($path)
  $wordCount = Get-BodyWordCount $raw '.html'
  if ($raw -notmatch '(?m)^adsense:\s*false\s*$') { $issues.Add("$name must keep AdSense disabled.") }
  if ($raw -match '(?m)^noindex:\s*true\s*$') { $issues.Add("$name is a core editorial page and must remain indexable.") }
  if ($raw -notmatch '(?m)^sources:\s*$') { $issues.Add("$name must list page-level sources.") }
  if ([regex]::Matches($raw, '(?m)^  - question:').Count -lt 3) { $issues.Add("$name must include at least 3 visible FAQ items.") }
  if ($wordCount -lt 900) { $issues.Add("$name has $wordCount words; expected at least 900.") }
}

$sitemap = [System.IO.File]::ReadAllText((Join-Path $root 'sitemap.xml'))
if ($sitemap -match 'site\.time') { $issues.Add('sitemap.xml still uses site.time for lastmod.') }

$firstStory = [System.IO.File]::ReadAllText((Join-Path $root '_posts\2026-05-28-first-story.md'))
if ($firstStory -notmatch '(?m)^noindex:\s*true\s*$') { $issues.Add('The unverified Corgi comparison must remain noindex until it is upgraded.') }

$fitCards = [System.IO.File]::ReadAllText((Join-Path $root 'pages\dog-fit-score-cards.html'))
$nonDiscreteWidths = [regex]::Matches($fitCards, 'style="width:\s*(\d+)%"') | Where-Object {
  ([int]$_.Groups[1].Value % 20) -ne 0
}
if ($nonDiscreteWidths.Count -gt 0) { $issues.Add('Fit Score Cards still contain non-discrete percentage widths.') }

$postFiles = Get-ChildItem (Join-Path $root '_posts') -Filter '*.md'
$postByUrl = @{}
foreach ($file in $postFiles) {
  if ($file.BaseName -match '^(\d{4})-(\d{2})-(\d{2})-(.+)$') {
    $postByUrl["/posts/$($Matches[1])/$($Matches[2])/$($Matches[3])/$($Matches[4])/"] = [System.IO.File]::ReadAllText($file.FullName)
  }
}

if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) {
  $issues.Add('Ruby is required to validate the Jekyll breed catalog.')
} else {
  $catalogPath = Join-Path $root '_data\breeds.yml'
  $catalogJson = & ruby -ryaml -rjson -e 'puts JSON.generate(YAML.load_file(ARGV[0]))' $catalogPath
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($catalogJson)) {
    $issues.Add('Could not parse _data/breeds.yml as YAML.')
  } else {
    try {
      $catalog = $catalogJson | ConvertFrom-Json
      $requiredBreedFields = @(
        'key', 'name', 'aliases', 'group', 'origin', 'breed_standard_url', 'publication_status', 'image_prefix', 'url',
        'summary', 'size', 'home', 'experience', 'kids', 'exercise', 'shedding', 'grooming', 'training', 'health_risk',
        'cost_level', 'caution', 'image'
      )
      $allowedStatuses = @('published', 'in_review', 'planned')

      if (@($catalog).Count -ne 279) {
        $issues.Add("Breed catalog has $(@($catalog).Count) entries; expected exactly 279.")
      }

      $duplicateKeys = @($catalog | Group-Object key | Where-Object { $_.Count -gt 1 })
      foreach ($duplicate in $duplicateKeys) {
        $issues.Add("Breed catalog repeats key '$($duplicate.Name)'.")
      }
      $duplicateUrls = @($catalog | Group-Object url | Where-Object { $_.Count -gt 1 })
      foreach ($duplicate in $duplicateUrls) {
        $issues.Add("Breed catalog repeats URL '$($duplicate.Name)'.")
      }

      foreach ($breed in $catalog) {
        foreach ($field in $requiredBreedFields) {
          $value = $breed.$field
          if ($null -eq $value -or ($field -ne 'aliases' -and [string]::IsNullOrWhiteSpace([string]$value))) {
            $issues.Add("Breed catalog entry '$($breed.key)' is missing '$field'.")
          }
        }
        if ($breed.publication_status -notin $allowedStatuses) {
          $issues.Add("Breed catalog entry '$($breed.key)' has invalid publication status '$($breed.publication_status)'.")
        }
        if ([string]$breed.breed_standard_url -notmatch '^https://') {
          $issues.Add("Breed catalog entry '$($breed.key)' needs an HTTPS official breed-standard URL.")
        }

        $postRaw = $postByUrl[[string]$breed.url]
        if ($breed.publication_status -eq 'published') {
          if ([string]::IsNullOrWhiteSpace($postRaw)) {
            $issues.Add("Published breed '$($breed.key)' has no matching post for $($breed.url).")
            continue
          }
          if ($postRaw -match '(?m)^noindex:\s*true\s*$') {
            $issues.Add("Published breed '$($breed.key)' still has noindex enabled.")
          }
          if ($postRaw -notmatch '(?m)^sources:\s*$') {
            $issues.Add("Published breed '$($breed.key)' has no page-level sources.")
          }
          if ([regex]::Matches($postRaw, '(?m)^  - question:\s*').Count -lt 3) {
            $issues.Add("Published breed '$($breed.key)' has fewer than 3 FAQ items.")
          }
          foreach ($variant in @('cover', 'main', 'play')) {
            $assetPath = Join-Path $root "assets\images\$($breed.image_prefix)-$variant.jpg"
            if (-not (Test-Path -LiteralPath $assetPath)) {
              $issues.Add("Published breed '$($breed.key)' is missing $variant image $($breed.image_prefix)-$variant.jpg.")
            }
          }
        } elseif ($breed.publication_status -eq 'in_review') {
          if ([string]::IsNullOrWhiteSpace($postRaw)) {
            $issues.Add("In-review breed '$($breed.key)' has no matching post for $($breed.url).")
          } else {
            if ($postRaw -notmatch '(?m)^noindex:\s*true\s*$') {
              $issues.Add("In-review breed '$($breed.key)' must remain noindex until it passes editorial checks.")
            }
            if ($postRaw -notmatch '(?m)^adsense:\s*false\s*$') {
              $issues.Add("In-review breed '$($breed.key)' must keep AdSense disabled until publication.")
            }
            if ($postRaw -notmatch '(?m)^sitemap:\s*false\s*$') {
              $issues.Add("In-review breed '$($breed.key)' must stay out of the sitemap until publication.")
            }
            if ([string]::IsNullOrWhiteSpace([string]$breed.review_batch)) {
              $issues.Add("In-review breed '$($breed.key)' is missing its review batch identifier.")
            }

            $sourceCount = [regex]::Matches($postRaw, '(?m)^  - organization:').Count
            $faqCount = [regex]::Matches($postRaw, '(?m)^  - question:').Count
            $wordCount = Get-BodyWordCount $postRaw '.md'
            $decisionHeadings = Get-CustomDecisionHeadings $postRaw
            $internalContentLinks = Get-InternalContentLinks $postRaw

            if ($postRaw -notmatch '(?m)^updated:\s*["'']?\d{4}-\d{2}-\d{2}["'']?\s*$') {
              $issues.Add("In-review breed '$($breed.key)' has no verified updated date.")
            }
            if ($sourceCount -lt 3) {
              $issues.Add("In-review breed '$($breed.key)' has only $sourceCount sources; expected at least 3.")
            }
            if ($faqCount -lt 3) {
              $issues.Add("In-review breed '$($breed.key)' has only $faqCount FAQ items; expected at least 3.")
            }
            if ($wordCount -lt 900) {
              $issues.Add("In-review breed '$($breed.key)' has $wordCount words; expected at least 900.")
            }
            if ($decisionHeadings.Count -lt 3) {
              $issues.Add("In-review breed '$($breed.key)' has only $($decisionHeadings.Count) breed-specific decision sections; expected at least 3.")
            }
            if ($internalContentLinks.Count -lt 2) {
              $issues.Add("In-review breed '$($breed.key)' has only $($internalContentLinks.Count) related internal content links; expected at least 2.")
            }
            if ($postRaw -match '(?m)^## .+ FAQ\s*$') {
              $issues.Add("In-review breed '$($breed.key)' duplicates FAQ content outside faq_schema.")
            }
            if ($postRaw.IndexOf([char]0x9225) -ge 0 -or $postRaw.IndexOf([char]0xFFFD) -ge 0) {
              $issues.Add("In-review breed '$($breed.key)' contains an encoding error.")
            }
            foreach ($variant in @('cover', 'main', 'play')) {
              $assetPath = Join-Path $root "assets\images\$($breed.image_prefix)-$variant.jpg"
              if (-not (Test-Path -LiteralPath $assetPath)) {
                $issues.Add("In-review breed '$($breed.key)' is missing $variant image $($breed.image_prefix)-$variant.jpg.")
              }
            }
          }
        } elseif (-not [string]::IsNullOrWhiteSpace($postRaw) -and $postRaw -notmatch '(?m)^noindex:\s*true\s*$') {
          $issues.Add("Planned breed '$($breed.key)' has a public post but is not marked published.")
        }
      }
    } catch {
      $issues.Add("Could not validate _data/breeds.yml: $($_.Exception.Message)")
    }
  }
}

$legacyHeadingPattern = '(?m)^## (Real-Life Fit Score|Exercise Needs|Grooming and Shedding|Feeding and Weight Control|Training Tips|Final Verdict|Space, Cost, and Family Q&A)\s*$'
$unsupportedInterviewPattern = '(?i)\b(based on (?:interviews|conversations)|interviewed|we spoke (?:with|to)|we asked)\b'

foreach ($file in $postFiles) {
  $raw = [System.IO.File]::ReadAllText($file.FullName)
  $headings = [regex]::Matches($raw, '(?m)^##\s+(.+?)\s*$') | ForEach-Object {
    $_.Groups[1].Value.Trim()
  }
  $decisionHeadings = Get-CustomDecisionHeadings $raw

  if ($raw -match $legacyHeadingPattern) {
    $issues.Add("$($file.Name) has a legacy shared-template heading: $($Matches[1]).")
  }
  if ($decisionHeadings.Count -lt 3) {
    $issues.Add("$($file.Name) has only $($decisionHeadings.Count) breed-specific decision sections; expected at least 3.")
  }
  if ($raw -notmatch '/dog-cost-calculator/' -or $raw -notmatch '/dog-fit-score-cards/') {
    $issues.Add("$($file.Name) must link directly to both dog decision tools.")
  }
  if ($raw -match $unsupportedInterviewPattern) {
    $issues.Add("$($file.Name) contains an unsupported interview claim.")
  }
  if ($raw -match '(?i)\bthe overlooked\b') {
    $issues.Add("$($file.Name) contains the repeated AI-style phrase 'the overlooked'.")
  }

  $hasSources = $raw -match '(?m)^sources:\s*$'
  $hasAds = $raw -match '(?m)^adsense:\s*true\s*$'
  $hasNoindex = $raw -match '(?m)^noindex:\s*true\s*$'
  $hasUpdated = $raw -match '(?m)^updated:\s*["'']?\d{4}-\d{2}-\d{2}["'']?\s*$'
  if (-not $hasSources) {
    if ($raw -notmatch '(?m)^adsense:\s*false\s*$') {
      $issues.Add("$($file.Name) has no sources and must keep AdSense disabled.")
    }
    if (-not $hasNoindex) {
      $issues.Add("$($file.Name) has no sources and must remain noindex until it is upgraded.")
    }
    if ($hasUpdated) {
      $issues.Add("$($file.Name) has no sources but still exposes a misleading updated date.")
    }
  } elseif (-not $hasUpdated) {
    $issues.Add("$($file.Name) has page-level sources but no updated date.")
  }
  if ($hasAds -and -not $hasSources) {
    $issues.Add("$($file.Name) enables AdSense without page-level sources.")
  }
}

if ($sitemap -notmatch 'post\.noindex' -or $sitemap -notmatch 'item\.noindex') {
  $issues.Add('sitemap.xml does not exclude noindex pages.')
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

Write-Host "Content quality checks passed for $($sourceReviewedPosts.Count) source-reviewed articles, $($adEligible.Count) AdSense-eligible pages, and $($postFiles.Count) directly maintained articles."
