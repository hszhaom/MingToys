param(
  [switch]$Preview,
  [string]$PreviewFile = "assets/images/husky-main.jpg",
  [string]$PreviewOut = "watermark-preview.jpg"
)

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class WatermarkInpainter
{
    public static void Clean(string inputPath, string outputPath)
    {
        using (var source = Image.FromFile(inputPath))
        using (var bitmap = new Bitmap(source.Width, source.Height, PixelFormat.Format24bppRgb))
        {
            using (var g = Graphics.FromImage(bitmap))
            {
                g.DrawImage(source, 0, 0, source.Width, source.Height);
            }

            int width = bitmap.Width;
            int height = bitmap.Height;
            int stride;
            byte[] pixels = ReadPixels(bitmap, out stride);
            byte[] original = (byte[])pixels.Clone();

            int x0 = (int)(width * 0.72);
            int y0 = (int)(height * 0.86);
            int x1 = width - 1;
            int y1 = height - 1;
            int rw = x1 - x0 + 1;
            int rh = y1 - y0 + 1;
            bool[,] mask = new bool[rw, rh];

            for (int y = y0; y <= y1; y++)
            {
                for (int x = x0; x <= x1; x++)
                {
                    int idx = y * stride + x * 3;
                    int b = original[idx];
                    int g = original[idx + 1];
                    int r = original[idx + 2];
                    int max = Math.Max(r, Math.Max(g, b));
                    int min = Math.Min(r, Math.Min(g, b));
                    int luma = (int)(0.299 * r + 0.587 * g + 0.114 * b);
                    bool paleText = luma > 138 && max - min < 72;
                    bool warmPlaque = r > 145 && g > 105 && b < 105 && r - b > 45;
                    bool nearBottomRight = x > width * 0.78 && y > height * 0.88;
                    if (nearBottomRight && (paleText || warmPlaque))
                    {
                        mask[x - x0, y - y0] = true;
                    }
                }
            }

            mask = Dilate(mask, rw, rh, 5);
            Inpaint(pixels, mask, width, height, stride, x0, y0, rw, rh, 170);
            Feather(pixels, mask, width, height, stride, x0, y0, rw, rh);
            WritePixels(bitmap, pixels, stride);
            SaveJpeg(bitmap, outputPath, 94L);
        }
    }

    private static void Inpaint(byte[] pixels, bool[,] mask, int width, int height, int stride, int x0, int y0, int rw, int rh, int iterations)
    {
        byte[] work = (byte[])pixels.Clone();
        for (int iter = 0; iter < iterations; iter++)
        {
            byte[] next = (byte[])work.Clone();
            for (int yy = 1; yy < rh - 1; yy++)
            {
                for (int xx = 1; xx < rw - 1; xx++)
                {
                    if (!mask[xx, yy]) continue;
                    int x = x0 + xx;
                    int y = y0 + yy;
                    int sumB = 0, sumG = 0, sumR = 0, count = 0;
                    for (int dy = -1; dy <= 1; dy++)
                    {
                        for (int dx = -1; dx <= 1; dx++)
                        {
                            if (dx == 0 && dy == 0) continue;
                            int idx2 = (y + dy) * stride + (x + dx) * 3;
                            sumB += work[idx2];
                            sumG += work[idx2 + 1];
                            sumR += work[idx2 + 2];
                            count++;
                        }
                    }
                    int idx = y * stride + x * 3;
                    next[idx] = (byte)(sumB / count);
                    next[idx + 1] = (byte)(sumG / count);
                    next[idx + 2] = (byte)(sumR / count);
                }
            }
            work = next;
        }
        Buffer.BlockCopy(work, 0, pixels, 0, pixels.Length);
    }

    private static void Feather(byte[] pixels, bool[,] mask, int width, int height, int stride, int x0, int y0, int rw, int rh)
    {
        byte[] copy = (byte[])pixels.Clone();
        for (int yy = 1; yy < rh - 1; yy++)
        {
            for (int xx = 1; xx < rw - 1; xx++)
            {
                if (!mask[xx, yy]) continue;
                int x = x0 + xx;
                int y = y0 + yy;
                int idx = y * stride + x * 3;
                int sumB = 0, sumG = 0, sumR = 0, count = 0;
                for (int dy = -1; dy <= 1; dy++)
                {
                    for (int dx = -1; dx <= 1; dx++)
                    {
                        int idx2 = (y + dy) * stride + (x + dx) * 3;
                        sumB += copy[idx2];
                        sumG += copy[idx2 + 1];
                        sumR += copy[idx2 + 2];
                        count++;
                    }
                }
                pixels[idx] = (byte)(sumB / count);
                pixels[idx + 1] = (byte)(sumG / count);
                pixels[idx + 2] = (byte)(sumR / count);
            }
        }
    }

    private static bool[,] Dilate(bool[,] source, int width, int height, int radius)
    {
        bool[,] result = new bool[width, height];
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                if (!source[x, y]) continue;
                for (int dy = -radius; dy <= radius; dy++)
                {
                    int yy = y + dy;
                    if (yy < 0 || yy >= height) continue;
                    for (int dx = -radius; dx <= radius; dx++)
                    {
                        int xx = x + dx;
                        if (xx < 0 || xx >= width) continue;
                        if (dx * dx + dy * dy <= radius * radius) result[xx, yy] = true;
                    }
                }
            }
        }
        return result;
    }

    private static byte[] ReadPixels(Bitmap bitmap, out int stride)
    {
        var rect = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
        var data = bitmap.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
        try
        {
            stride = data.Stride;
            byte[] pixels = new byte[stride * bitmap.Height];
            Marshal.Copy(data.Scan0, pixels, 0, pixels.Length);
            return pixels;
        }
        finally
        {
            bitmap.UnlockBits(data);
        }
    }

    private static void WritePixels(Bitmap bitmap, byte[] pixels, int stride)
    {
        var rect = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
        var data = bitmap.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format24bppRgb);
        try
        {
            Marshal.Copy(pixels, 0, data.Scan0, pixels.Length);
        }
        finally
        {
            bitmap.UnlockBits(data);
        }
    }

    private static void SaveJpeg(Bitmap bitmap, string outputPath, long quality)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outputPath)));
        ImageCodecInfo encoder = null;
        foreach (var codec in ImageCodecInfo.GetImageEncoders())
        {
            if (codec.MimeType == "image/jpeg") { encoder = codec; break; }
        }
        var parameters = new EncoderParameters(1);
        parameters.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, quality);
        bitmap.Save(outputPath, encoder, parameters);
    }
}
"@

if ($Preview) {
  [WatermarkInpainter]::Clean((Resolve-Path $PreviewFile), (Join-Path (Get-Location) $PreviewOut))
  Write-Output "Preview written: $PreviewOut"
} else {
  $files = Get-ChildItem "assets/images" -File -Filter "*.jpg"
  $count = 0
  foreach ($file in $files) {
    $temp = "$($file.FullName).tmp.jpg"
    [WatermarkInpainter]::Clean($file.FullName, $temp)
    Move-Item -LiteralPath $temp -Destination $file.FullName -Force
    $count++
  }
  Write-Output "Processed $count JPG images"
}
