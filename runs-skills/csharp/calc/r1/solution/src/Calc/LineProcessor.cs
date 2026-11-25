using System.Buffers;
using System.Buffers.Text;

namespace Calc;

/// <summary>
/// Streams newline-delimited expressions from an input stream and writes one result per
/// non-blank line to an output stream.
/// </summary>
public static class LineProcessor
{
    private const int BufferSize = 64 * 1024;
    private static ReadOnlySpan<byte> ErrorText => "error\n"u8;

    public static void Run(Stream input, Stream output)
    {
        ArgumentNullException.ThrowIfNull(input);
        ArgumentNullException.ThrowIfNull(output);

        var evaluator = new ExpressionEvaluator();
        using var writer = new BufferedStream(output, BufferSize);
        byte[] buffer = ArrayPool<byte>.Shared.Rent(BufferSize);
        try
        {
            int filled = 0;
            while (true)
            {
                if (filled == buffer.Length)
                {
                    byte[] larger = ArrayPool<byte>.Shared.Rent(buffer.Length * 2);
                    buffer.AsSpan(0, filled).CopyTo(larger);
                    ArrayPool<byte>.Shared.Return(buffer);
                    buffer = larger;
                }

                int read = input.Read(buffer, filled, buffer.Length - filled);
                if (read == 0)
                {
                    break;
                }

                int scanFrom = filled;
                filled += read;
                int lineStart = 0;
                int newline;
                while ((newline = buffer.AsSpan(scanFrom, filled - scanFrom).IndexOf((byte)'\n')) >= 0)
                {
                    int lineEnd = scanFrom + newline;
                    ProcessLine(evaluator, buffer.AsSpan(lineStart, lineEnd - lineStart), writer);
                    lineStart = lineEnd + 1;
                    scanFrom = lineStart;
                }

                int remaining = filled - lineStart;
                buffer.AsSpan(lineStart, remaining).CopyTo(buffer);
                filled = remaining;
            }

            if (filled > 0)
            {
                ProcessLine(evaluator, buffer.AsSpan(0, filled), writer);
            }
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer);
        }
    }

    private static void ProcessLine(ExpressionEvaluator evaluator, ReadOnlySpan<byte> line, Stream writer)
    {
        if (line.IndexOfAnyExcept((byte)' ', (byte)'\t') < 0)
        {
            return;
        }

        if (!evaluator.TryEvaluate(line, out long value))
        {
            writer.Write(ErrorText);
            return;
        }

        Span<byte> text = stackalloc byte[21];
        Utf8Formatter.TryFormat(value, text, out int written);
        text[written++] = (byte)'\n';
        writer.Write(text[..written]);
    }
}
