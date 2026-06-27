Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class CornerCleaner
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

            int x0 = (int)(width * 0.765);
            int y0 = (int)(height * 0.895);
            int x1 = width - 1;
            int y1 = height - 1;
            int offsetX = Math.Max(18, (int)(width * 0.18));
            int offsetY = Math.Max(14, (int)(height * 0.065));

            for (int y = y0; y <= y1; y++)
            {
                double fy = EdgeWeight(y, y0, y1);
                for (int x = x0; x <= x1; x++)
                {
                    double fx = EdgeWeight(x, x0, x1);
                    double alpha = Math.Min(fx, fy);

                    int sx = Math.Max(0, Math.Min(width - 1, x - offsetX));
                    int sy = Math.Max(0, Math.Min(height - 1, y - offsetY));
                    int count = 0;
                    int sumR = 0, sumG = 0, sumB = 0;

                    for (int dy = -5; dy <= 5; dy++)
                    {
                        int yy = Math.Max(0, Math.Min(height - 1, sy + dy));
                        for (int dx = -5; dx <= 5; dx++)
                        {
                            int xx = Math.Max(0, Math.Min(width - 1, sx + dx));
                            int sidx = yy * stride + xx * 3;
                            sumB += original[sidx];
                            sumG += original[sidx + 1];
                            sumR += original[sidx + 2];
                            count++;
                        }
                    }

                    int idx = y * stride + x * 3;
                    int nb = sumB / count;
                    int ng = sumG / count;
                    int nr = sumR / count;

                    pixels[idx] = Blend(original[idx], nb, alpha);
                    pixels[idx + 1] = Blend(original[idx + 1], ng, alpha);
                    pixels[idx + 2] = Blend(original[idx + 2], nr, alpha);
                }
            }

            WritePixels(bitmap, pixels, stride);
            SaveJpeg(bitmap, outputPath, 94L);
        }
    }

    private static double EdgeWeight(int value, int start, int end)
    {
        int feather = Math.Max(10, (end - start) / 12);
        double left = Math.Min(1.0, Math.Max(0.0, (double)(value - start) / feather));
        double right = Math.Min(1.0, Math.Max(0.0, (double)(end - value) / feather));
        return Math.Min(left, right);
    }

    private static byte Blend(byte oldValue, int newValue, double alpha)
    {
        alpha = Math.Max(0.0, Math.Min(1.0, alpha));
        return (byte)Math.Max(0, Math.Min(255, oldValue * (1.0 - alpha) + newValue * alpha));
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
        ImageCodecInfo encoder = null;
        foreach (var codec in ImageCodecInfo.GetImageEncoders())
        {
            if (codec.MimeType == "image/jpeg")
            {
                encoder = codec;
                break;
            }
        }
        var parameters = new EncoderParameters(1);
        parameters.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, quality);
        bitmap.Save(outputPath, encoder, parameters);
    }
}
"@

$files = Get-ChildItem "assets/images" -File -Filter "*.jpg"
$count = 0
foreach ($file in $files) {
  $temp = "$($file.FullName).tmp.jpg"
  [CornerCleaner]::Clean($file.FullName, $temp)
  Move-Item -LiteralPath $temp -Destination $file.FullName -Force
  $count++
}
Write-Output "Processed $count JPG images"
