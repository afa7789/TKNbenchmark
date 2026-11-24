using System.Buffers;

namespace Calc;

/// <summary>Reads newline-delimited expressions and writes one result per non-blank line.</summary>
public static class LineProcessor
{
    public static void Run(Stream input, TextWriter output)
    {
        var buffer = new ArrayBufferWriter<byte>(1 << 16);
        Span<byte> chunk = stackalloc byte[1 << 16];
        int read;

        while ((read = input.Read(chunk)) > 0)
        {
            ReadOnlySpan<byte> data = chunk[..read];
            int newline;
            while ((newline = data.IndexOf((byte)'\n')) >= 0)
            {
                if (buffer.WrittenCount == 0)
                {
                    Emit(data[..newline], output);
                }
                else
                {
                    buffer.Write(data[..newline]);
                    Emit(buffer.WrittenSpan, output);
                    buffer.ResetWrittenCount();
                }

                data = data[(newline + 1)..];
            }

            buffer.Write(data);
        }

        if (buffer.WrittenCount > 0)
        {
            Emit(buffer.WrittenSpan, output);
        }
    }

    private static void Emit(ReadOnlySpan<byte> line, TextWriter output)
    {
        if (IsBlank(line))
        {
            return;
        }

        if (Evaluator.TryEvaluate(line, out long value))
        {
            output.WriteLine(value);
        }
        else
        {
            output.WriteLine("error");
        }
    }

    private static bool IsBlank(ReadOnlySpan<byte> line) =>
        line.IndexOfAnyExcept((byte)' ', (byte)'\t') < 0;
}
