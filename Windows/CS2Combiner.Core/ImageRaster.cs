using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats;
using SixLabors.ImageSharp.Formats.Png;
using SixLabors.ImageSharp.PixelFormats;

namespace CS2Combiner.Core;

public sealed class ImageRaster
{
    public ImageRaster(int width, int height, byte[] bytes)
    {
        if (bytes.Length != checked(width * height * 4))
        {
            throw new ArgumentException("RGBA raster byte length does not match its dimensions.", nameof(bytes));
        }

        Width = width;
        Height = height;
        Bytes = bytes;
    }

    public int Width { get; }
    public int Height { get; }
    public byte[] Bytes { get; }
    public PixelSize Size => new(Width, Height);
    public byte Red(int pixel) => Bytes[pixel * 4];

    public ImageRaster Clone() => new(Width, Height, (byte[])Bytes.Clone());

    public static ImageRaster Solid(PixelSize size, byte red, byte green, byte blue, byte alpha = 255)
    {
        var bytes = new byte[checked(size.Width * size.Height * 4)];
        for (var pixel = 0; pixel < size.Width * size.Height; pixel++)
        {
            var index = pixel * 4;
            bytes[index] = red;
            bytes[index + 1] = green;
            bytes[index + 2] = blue;
            bytes[index + 3] = alpha;
        }

        return new(size.Width, size.Height, bytes);
    }
}

public static class ImageCodec
{
    public static PixelSize Dimensions(string path)
    {
        try
        {
            var info = Image.Identify(path);
            return new(info.Width, info.Height);
        }
        catch (Exception error) when (error is UnknownImageFormatException or InvalidImageContentException or IOException)
        {
            throw new CombinerException($"Could not read image data from {Path.GetFileName(path)}.");
        }
    }

    public static bool HasAlphaChannel(string path)
    {
        try
        {
            var info = Image.Identify(path);
            if (string.Equals(info.Metadata.DecodedImageFormat?.Name, "PNG", StringComparison.OrdinalIgnoreCase))
            {
                var colorType = info.Metadata.GetPngMetadata().ColorType;
                return colorType is PngColorType.RgbWithAlpha or PngColorType.GrayscaleWithAlpha;
            }

            if (string.Equals(info.Metadata.DecodedImageFormat?.Name, "JPEG", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            return info.PixelType.AlphaRepresentation != PixelAlphaRepresentation.None;
        }
        catch (Exception error) when (error is UnknownImageFormatException or InvalidImageContentException or IOException)
        {
            throw new CombinerException($"Could not read image data from {Path.GetFileName(path)}.");
        }
    }

    public static ImageRaster Load(string path)
    {
        try
        {
            using var image = Image.Load<Rgba32>(path);
            var pixels = new Rgba32[checked(image.Width * image.Height)];
            image.CopyPixelDataTo(pixels);
            var bytes = new byte[checked(pixels.Length * 4)];
            for (var pixel = 0; pixel < pixels.Length; pixel++)
            {
                var index = pixel * 4;
                bytes[index] = pixels[pixel].R;
                bytes[index + 1] = pixels[pixel].G;
                bytes[index + 2] = pixels[pixel].B;
                bytes[index + 3] = pixels[pixel].A;
            }

            return new(image.Width, image.Height, bytes);
        }
        catch (Exception error) when (error is UnknownImageFormatException or InvalidImageContentException or IOException)
        {
            throw new CombinerException($"Could not read image data from {Path.GetFileName(path)}.");
        }
    }

    public static void WritePng(ImageRaster raster, string path)
    {
        try
        {
            var pixels = new Rgba32[checked(raster.Width * raster.Height)];
            for (var pixel = 0; pixel < pixels.Length; pixel++)
            {
                var index = pixel * 4;
                pixels[pixel] = new(
                    raster.Bytes[index],
                    raster.Bytes[index + 1],
                    raster.Bytes[index + 2],
                    raster.Bytes[index + 3]);
            }

            using var image = Image.LoadPixelData<Rgba32>(pixels, raster.Width, raster.Height);
            image.SaveAsPng(path, new PngEncoder
            {
                BitDepth = PngBitDepth.Bit8,
                ColorType = PngColorType.RgbWithAlpha
            });
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new CombinerException($"Could not write {Path.GetFileName(path)}.");
        }
    }
}
