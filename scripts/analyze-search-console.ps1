[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateScript({ Test-Path -LiteralPath $_ })]
  [string]$QueriesCsv,

  [ValidateScript({ -not $_ -or (Test-Path -LiteralPath $_) })]
  [string]$PagesCsv,

  [string]$OutPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'reports\search-console-content-opportunities.csv')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Get-ColumnName {
  param([object]$Row, [string[]]$Candidates)

  foreach ($candidate in $Candidates) {
    if ($Row.PSObject.Properties.Name -contains $candidate) { return $candidate }
  }
  throw "Required CSV column is missing. Expected one of: $($Candidates -join ', ')."
}

function Convert-GscNumber {
  param([object]$Value)

  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) { return 0 }
  $normalized = $text.Replace(',', '').Replace('%', '').Trim()
  $number = 0.0
  if (-not [double]::TryParse($normalized, [ref]$number)) {
    throw "Cannot read numeric Search Console value '$text'."
  }
  return $number
}

function Get-Intent {
  param([string]$Query)

  $text = $Query.ToLowerInvariant()
  if ($text -match '\b(cost|price|budget|expense|insurance|how much)\b') { return 'Cost and long-term ownership' }
  if ($text -match '\b(apartment|house|yard|small space|city)\b') { return 'Space and housing fit' }
  if ($text -match '\b(family|kids|children|first[- ]time|beginner|alone|work)\b') { return 'Family and routine fit' }
  if ($text -match '\b(groom|shed|shedding|coat)\b') { return 'Grooming and shedding' }
  if ($text -match '\b(health|lifespan|life span|disease|allerg)\b') { return 'Health and screening' }
  if ($text -match '\b(train|training|bark|bite|aggress|recall)\b') { return 'Training and behavior management' }
  return 'General breed research'
}

function Get-LocalPages {
  $items = New-Object System.Collections.Generic.List[object]
  foreach ($post in Get-ChildItem (Join-Path $root '_posts') -Filter '*.md') {
    $raw = [System.IO.File]::ReadAllText($post.FullName)
    if ($raw -match '(?m)^noindex:\s*true\s*$') { continue }
    $title = ([regex]::Match($raw, '(?m)^title:\s*"?(.+?)"?\s*$')).Groups[1].Value
    $match = [regex]::Match($post.Name, '^(\d{4})-(\d{2})-(\d{2})-(.+)\.md$')
    if (-not $match.Success) { continue }
    $items.Add([pscustomobject]@{
      Title = $title
      Url = "/posts/$($match.Groups[1].Value)/$($match.Groups[2].Value)/$($match.Groups[3].Value)/$($match.Groups[4].Value)/"
      SearchText = (($title + ' ' + $match.Groups[4].Value.Replace('-', ' ')).ToLowerInvariant())
    })
  }
  foreach ($page in Get-ChildItem (Join-Path $root 'pages') -Filter '*.html') {
    $raw = [System.IO.File]::ReadAllText($page.FullName)
    if ($raw -match '(?m)^noindex:\s*true\s*$') { continue }
    $title = ([regex]::Match($raw, '(?m)^title:\s*"?(.+?)"?\s*$')).Groups[1].Value
    $permalink = ([regex]::Match($raw, '(?m)^permalink:\s*(/[^\s]+/)\s*$')).Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($permalink)) { continue }
    $items.Add([pscustomobject]@{
      Title = $title
      Url = $permalink
      SearchText = (($title + ' ' + $permalink.Replace('/', ' ')).ToLowerInvariant())
    })
  }
  return $items
}

$queryRows = Import-Csv -LiteralPath $QueriesCsv
if ($queryRows.Count -eq 0) { throw 'The query export is empty.' }
$queryCandidates = @('Queries', 'Query', 'Top queries', ([string]::Concat([char]0x67E5, [char]0x8BE2)))
$clickCandidates = @('Clicks', ([string]::Concat([char]0x70B9, [char]0x51FB)))
$impressionCandidates = @('Impressions', ([string]::Concat([char]0x5C55, [char]0x793A)))
$ctrCandidates = @('CTR', ([string]::Concat([char]0x70B9, [char]0x51FB, [char]0x7387)))
$positionCandidates = @('Position', 'Average position', ([string]::Concat([char]0x5E73, [char]0x5747, [char]0x6392, [char]0x540D)))
$queryColumn = Get-ColumnName -Row $queryRows[0] -Candidates $queryCandidates
$clicksColumn = Get-ColumnName -Row $queryRows[0] -Candidates $clickCandidates
$impressionsColumn = Get-ColumnName -Row $queryRows[0] -Candidates $impressionCandidates
$ctrColumn = Get-ColumnName -Row $queryRows[0] -Candidates $ctrCandidates
$positionColumn = Get-ColumnName -Row $queryRows[0] -Candidates $positionCandidates
$localPages = Get-LocalPages

$pageLookup = @{}
if ($PagesCsv) {
  $pageRows = Import-Csv -LiteralPath $PagesCsv
  if ($pageRows.Count -gt 0) {
    $pageCandidates = @('Pages', 'Page', ([string]::Concat([char]0x7F51, [char]0x9875)))
    $pageColumn = Get-ColumnName -Row $pageRows[0] -Candidates $pageCandidates
    foreach ($row in $pageRows) {
      $pageLookup[([string]$row.$pageColumn).TrimEnd('/')] = $true
    }
  }
}

$results = foreach ($row in $queryRows) {
  $query = ([string]$row.$queryColumn).Trim()
  if ([string]::IsNullOrWhiteSpace($query)) { continue }
  $queryWords = @($query.ToLowerInvariant() -split '\s+' | Where-Object { $_.Length -gt 2 } | Select-Object -Unique)
  $match = $localPages |
    ForEach-Object {
      $candidatePage = $_
      $matchedWords = @($queryWords | Where-Object { $candidatePage.SearchText -match [regex]::Escape($_) })
      [pscustomobject]@{ Page = $candidatePage; Score = $matchedWords.Count }
    } |
    Sort-Object Score -Descending |
    Select-Object -First 1

  $impressions = Convert-GscNumber $row.$impressionsColumn
  $clicks = Convert-GscNumber $row.$clicksColumn
  $position = Convert-GscNumber $row.$positionColumn
  $target = if ($match.Score -ge [Math]::Min(2, $queryWords.Count)) { $match.Page } else { $null }
  $recommendation = if ($target) {
    if ($impressions -ge 20 -and $position -le 30) { 'Expand this existing URL; do not create a competing page.' } else { 'Monitor intent before changing this existing URL.' }
  } elseif ($impressions -ge 20) {
    'Research 3+ verifiable sources and internal links before proposing a new page.'
  } else {
    'Do not publish from this query alone; monitor for sustained demand.'
  }

  [pscustomobject]@{
    Query = $query
    Clicks = $clicks
    Impressions = $impressions
    CTR = $row.$ctrColumn
    AveragePosition = $position
    Intent = Get-Intent $query
    ExistingUrl = if ($target) { $target.Url } else { '' }
    ExistingTitle = if ($target) { $target.Title } else { '' }
    CandidatePageSeenInPageExport = if ($target -and $pageLookup.Count -gt 0) {
      $pageLookup.ContainsKey(("https://petstorie.com" + $target.Url).TrimEnd('/'))
    } else {
      $null
    }
    Recommendation = $recommendation
  }
}

$destination = Split-Path -Parent $OutPath
if (-not (Test-Path -LiteralPath $destination)) {
  New-Item -ItemType Directory -Path $destination -Force | Out-Null
}
$results |
  Sort-Object -Property Impressions -Descending |
  Export-Csv -LiteralPath $OutPath -NoTypeInformation -Encoding utf8

Write-Host "Analyzed $($results.Count) Search Console queries. Report written to $OutPath"
