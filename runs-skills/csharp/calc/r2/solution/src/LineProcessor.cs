using System.Buffers;
using System.Globalization;
using System.Text;

namespace Calc;

/// <summary>Reads newline-separated expressions and writes one result per non-blank line.</summary>
internal static class LineProcessor
{
    private static readonly byte[] ErrorBytes = "error\n"u8.ToArray();

    public static void Process(Stream input, Stream output)
    {
        ArgumentNullException.ThrowIfNull(input);
        ArgumentNullException.ThrowIfNull(output);

        byte[] data = ReadAll(input);
        using var writer = new BufferedStream(output, 1 << 16);
        Span<byte> number = stackalloc byte[24];

        ReadOnlySpan<byte> remaining = data;
        while (!remaining.IsEmpty)
        {
            int newline = remaining.IndexOf((byte)'\n');
            ReadOnlySpan<byte> line = newline < 0 ? remaining : remaining[..newline];
            remaining = newline < 0 ? [] : remaining[(newline + 1)..];

            if (IsBlank(line))
            {
                continue;
            }

            if (Evaluator.TryEvaluate(line, out long value)
                && value.TryFormat(number, out int written, provider: CultureInfo.InvariantCulture))
            {
                number[written++] = (byte)'\n';
                writer.Write(number[..written]);
            }
            else
            {
                writer.Write(ErrorBytes);
            }
        }
    }

    private static bool IsBlank(ReadOnlySpan<byte> line) => line.IndexOfAnyExcept((byte)' ', (byte)'\t') < 0;

    private static byte[] ReadAll(Stream input)
    {
        using var buffer = new MemoryStream();
        input.CopyTo(buffer);
        return buffer.ToArray();
    }
}
