using System.Buffers;

namespace Calc;

/// <summary>Streams newline-delimited expressions from input and writes one result per line.</summary>
internal static class LineProcessor
{
    private const int BufferSize = 1 << 16;

    private static ReadOnlySpan<byte> ErrorText => "error"u8;

    public static void Run(Stream input, Stream output)
    {
        using var writer = new BufferedStream(output, BufferSize);
        var pending = new ArrayBufferWriter<byte>(BufferSize);
        byte[] chunk = new byte[BufferSize];

        int read;
        while ((read = input.Read(chunk, 0, chunk.Length)) > 0)
        {
            ReadOnlySpan<byte> data = chunk.AsSpan(0, read);
            int newline;
            while ((newline = data.IndexOf((byte)'\n')) >= 0)
            {
                ReadOnlySpan<byte> line = data[..newline];
                if (pending.WrittenCount > 0)
                {
                    // Complete a line that straddled a chunk boundary.
                    pending.Write(line);
                    ProcessLine(pending.WrittenSpan, writer);
                    pending.ResetWrittenCount();
                }
                else
                {
                    ProcessLine(line, writer);
                }

                data = data[(newline + 1)..];
            }

            pending.Write(data);
        }

        // Final line without a trailing newline.
        if (pending.WrittenCount > 0)
        {
            ProcessLine(pending.WrittenSpan, writer);
        }

        writer.Flush();
    }

    private static void ProcessLine(ReadOnlySpan<byte> line, Stream writer)
    {
        if (Evaluator.IsBlank(line))
        {
            return;
        }

        Span<byte> digits = stackalloc byte[24];
        if (Evaluator.TryEvaluate(line, out long value) && value.TryFormat(digits, out int written))
        {
            writer.Write(digits[..written]);
        }
        else
        {
            writer.Write(ErrorText);
        }

        writer.WriteByte((byte)'\n');
    }
}
