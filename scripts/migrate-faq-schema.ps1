param(
  [Parameter(Mandatory = $true)]
  [string[]]$Path,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function ConvertTo-YamlDoubleQuoted {
  param([string]$Value)

  $clean = [regex]::Replace($Value, '\[([^\]]+)\]\([^\)]+\)', '$1')
  $clean = $clean.Replace('**', '').Replace('__', '').Replace('`', '')
  $clean = [regex]::Replace($clean, '\s+', ' ').Trim()
  return $clean.Replace('\', '\\').Replace('"', '\"')
}

foreach ($item in $Path) {
  $resolved = Resolve-Path -LiteralPath $item
  $raw = [System.IO.File]::ReadAllText($resolved)

  if ($raw -match '(?m)^faq_schema:') {
    Write-Host "$item already has faq_schema; skipped."
    continue
  }

  $frontMatter = [regex]::Match($raw, '(?s)\A---\r?\n(?<body>.*?)\r?\n---\r?\n')
  if (-not $frontMatter.Success) {
    throw "$item does not have valid YAML front matter."
  }

  $faqSection = [regex]::Match($raw, '(?ms)^## [^\r\n]*FAQ\r?\n(?<body>.*?)(?=^## |\z)')
  if (-not $faqSection.Success) {
    throw "$item does not contain a Markdown FAQ section."
  }

  $faqItems = [regex]::Matches($faqSection.Groups['body'].Value, '(?ms)^### (?<question>[^\r\n]+)\r?\n\s*(?<answer>.*?)(?=^### |\z)')
  if ($faqItems.Count -lt 3) {
    throw "$item only produced $($faqItems.Count) FAQ items."
  }

  $yaml = New-Object System.Collections.Generic.List[string]
  $yaml.Add('faq_schema:')
  foreach ($faqItem in $faqItems) {
    $question = ConvertTo-YamlDoubleQuoted $faqItem.Groups['question'].Value
    $answer = ConvertTo-YamlDoubleQuoted $faqItem.Groups['answer'].Value
    $yaml.Add("  - question: `"$question`"")
    $yaml.Add("    answer: `"$answer`"")
  }

  $lineEnding = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
  $yamlBlock = ($yaml -join $lineEnding) + $lineEnding
  $newFrontMatter = $frontMatter.Groups['body'].Value.TrimEnd() + $lineEnding + $yamlBlock
  $newRaw = '---' + $lineEnding + $newFrontMatter + '---' + $lineEnding
  $newRaw += $raw.Substring($frontMatter.Length)
  $newRaw = $newRaw.Remove($faqSection.Index + ($newRaw.Length - $raw.Length), $faqSection.Length).TrimEnd() + $lineEnding

  Write-Host "${item}: $($faqItems.Count) FAQ items ready."
  if ($Apply) {
    [System.IO.File]::WriteAllText($resolved, $newRaw, $utf8NoBom)
  }
}
