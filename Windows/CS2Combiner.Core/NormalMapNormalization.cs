namespace CS2Combiner.Core;

public static class NormalMapNormalization
{
    public static void Normalize(ImageRaster raster)
    {
        for (var pixel = 0; pixel < raster.Width * raster.Height; pixel++)
        {
            var index = pixel * 4;
            var normalized = NormalizedComponents(
                raster.Bytes[index],
                raster.Bytes[index + 1],
                raster.Bytes[index + 2]);
            raster.Bytes[index] = normalized.Red;
            raster.Bytes[index + 1] = normalized.Green;
            raster.Bytes[index + 2] = normalized.Blue;
        }
    }

    public static (byte Red, byte Green, byte Blue) NormalizedComponents(
        byte red,
        byte green,
        byte blue)
    {
        const double maximum = byte.MaxValue;
        var x = red / maximum * 2.0 - 1.0;
        var y = green / maximum * 2.0 - 1.0;
        var z = blue / maximum * 2.0 - 1.0;
        var length = Math.Sqrt(x * x + y * y + z * z);

        if (length <= 0.000_001)
        {
            return ((byte)(maximum * 0.5), (byte)(maximum * 0.5), byte.MaxValue);
        }

        static byte Encode(double value, double vectorLength)
        {
            var unit = Math.Max(-1.0, Math.Min(1.0, value / vectorLength));
            return (byte)Math.Round(
                (unit * 0.5 + 0.5) * byte.MaxValue,
                MidpointRounding.AwayFromZero);
        }

        return (Encode(x, length), Encode(y, length), Encode(z, length));
    }
}
