[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)]
  [string]$ManifestPath,

  [string]$Endpoint = $(if ($env:SQUAREFACE_IMAGE_ENDPOINT) { $env:SQUAREFACE_IMAGE_ENDPOINT } else { 'https://api.squarefaceicon.org/v1/images/generations' }),

  [string]$ApiKey = $env:SQUAREFACE_API_KEY,

  [string]$Model = $(if ($env:SQUAREFACE_IMAGE_MODEL) { $env:SQUAREFACE_IMAGE_MODEL } else { 'gpt-image-1' }),

  [int]$TimeoutSeconds = 180,

  [int]$MaxAssets = 0,

  [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

function Get-ResponseImageBytes {
  param(
    [Parameter(Mandatory)]$ResponseData,
    [Parameter(Mandatory)][System.Net.Http.HttpClient]$Client
  )

  if ($ResponseData.b64_json) {
    return [Convert]::FromBase64String([string]$ResponseData.b64_json)
  }

  $imageUrl = if ($ResponseData.url) { [string]$ResponseData.url } elseif ($ResponseData.image_url) { [string]$ResponseData.image_url } else { $null }
  if ([string]::IsNullOrWhiteSpace($imageUrl)) {
    throw 'The image API response did not contain data[0].b64_json, data[0].url, or data[0].image_url.'
  }

  return $Client.GetByteArrayAsync($imageUrl).GetAwaiter().GetResult()
}

function Save-NormalizedJpeg {
  param(
    [Parameter(Mandatory)][byte[]]$ImageBytes,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][int]$TargetWidth,
    [Parameter(Mandatory)][int]$TargetHeight
  )

  Add-Type -AssemblyName System.Drawing
  $inputStream = New-Object System.IO.MemoryStream(, $ImageBytes)
  $source = [System.Drawing.Image]::FromStream($inputStream, $true, $true)
  try {
    if ($source.Width -lt 128 -or $source.Height -lt 128) {
      throw "Generated image is too small ($($source.Width)x$($source.Height))."
    }

    $scale = [Math]::Max($TargetWidth / [double]$source.Width, $TargetHeight / [double]$source.Height)
    $scaledWidth = [int][Math]::Ceiling($source.Width * $scale)
    $scaledHeight = [int][Math]::Ceiling($source.Height * $scale)
    $offsetX = [int][Math]::Floor(($TargetWidth - $scaledWidth) / 2)
    $offsetY = [int][Math]::Floor(($TargetHeight - $scaledHeight) / 2)

    $bitmap = New-Object System.Drawing.Bitmap($TargetWidth, $TargetHeight)
    try {
      $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
      try {
        $graphics.Clear([System.Drawing.Color]::White)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.DrawImage($source, $offsetX, $offsetY, $scaledWidth, $scaledHeight)

        $directory = Split-Path -Parent $OutputPath
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
        $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
        $parameters = New-Object System.Drawing.Imaging.EncoderParameters(1)
        try {
          $parameters.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 92L)
          $bitmap.Save($OutputPath, $encoder, $parameters)
        } finally {
          $parameters.Dispose()
        }
      } finally {
        $graphics.Dispose()
      }
    } finally {
      $bitmap.Dispose()
    }
  } finally {
    $source.Dispose()
    $inputStream.Dispose()
  }

  $verification = [System.Drawing.Image]::FromFile($OutputPath)
  try {
    if ($verification.Width -ne $TargetWidth -or $verification.Height -ne $TargetHeight) {
      throw "JPEG validation failed for $OutputPath. Expected ${TargetWidth}x${TargetHeight}; found $($verification.Width)x$($verification.Height)."
    }
  } finally {
    $verification.Dispose()
  }
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  throw 'SQUAREFACE_API_KEY is not set. Set it for this PowerShell session; do not commit it to the repository.'
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "Manifest does not exist: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if (-not $manifest.assets -or @($manifest.assets).Count -eq 0) {
  throw 'The manifest must contain at least one asset.'
}

$root = Split-Path -Parent $PSScriptRoot
$handler = New-Object System.Net.Http.HttpClientHandler
$client = New-Object System.Net.Http.HttpClient($handler)
$client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

try {
  $completed = 0
  foreach ($asset in $manifest.assets) {
    if ($MaxAssets -gt 0 -and $completed -ge $MaxAssets) {
      break
    }

    foreach ($field in @('path', 'api_size', 'width', 'height', 'prompt')) {
      if ([string]::IsNullOrWhiteSpace([string]$asset.$field)) {
        throw "Manifest asset is missing '$field'."
      }
    }

    $outputPath = Join-Path $root ([string]$asset.path)
    if ((Test-Path -LiteralPath $outputPath) -and -not $Overwrite) {
      Write-Host "SKIP: $($asset.path) already exists. Use -Overwrite only after reviewing the current file."
      continue
    }

    if (-not $PSCmdlet.ShouldProcess($outputPath, 'Generate, normalize, and save breed image')) {
      continue
    }

    $payload = @{
      model = $Model
      prompt = [string]$asset.prompt
      size = [string]$asset.api_size
      response_format = 'b64_json'
      n = 1
    } | ConvertTo-Json -Compress

    $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, $Endpoint)
    $request.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $ApiKey)
    $request.Content = New-Object System.Net.Http.StringContent($payload, [System.Text.Encoding]::UTF8, 'application/json')

    Write-Host "GENERATE: $($asset.path)"
    $response = $client.SendAsync($request).GetAwaiter().GetResult()
    try {
      $responseText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
      if (-not $response.IsSuccessStatusCode) {
        $excerpt = $responseText.Substring(0, [Math]::Min(800, $responseText.Length))
        throw "SquareFace API returned $([int]$response.StatusCode) for $($asset.path): $excerpt"
      }

      $responseJson = $responseText | ConvertFrom-Json
      if (-not $responseJson.data -or @($responseJson.data).Count -lt 1) {
        throw "SquareFace API returned no image data for $($asset.path)."
      }

      $imageBytes = Get-ResponseImageBytes -ResponseData $responseJson.data[0] -Client $client
      Save-NormalizedJpeg -ImageBytes $imageBytes -OutputPath $outputPath -TargetWidth ([int]$asset.width) -TargetHeight ([int]$asset.height)
      $completed++
      Write-Host "SAVED: $($asset.path)"
    } finally {
      $response.Dispose()
      $request.Dispose()
    }
  }
} finally {
  $client.Dispose()
  $handler.Dispose()
}
