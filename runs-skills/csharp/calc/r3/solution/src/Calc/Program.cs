using System.Buffers.Text;
using Calc;

// Deeply nested input recurses deeply; run on a thread with a generous stack.
const int StackSize = 512 * 1024 * 1024;

var worker = new Thread(Run, StackSize);
worker.Start();
worker.Join();
return 0;

static void Run()
{
    byte[] input;
    using (var stdin = Console.OpenStandardInput())
    using (var buffer = new MemoryStream())
    {
        stdin.CopyTo(buffer);
        input = buffer.ToArray();
    }

    using var stdout = new BufferedStream(Console.OpenStandardOutput(), 1 << 16);
    ReadOnlySpan<byte> errorLine = "error\n"u8;
    Span<byte> number = stackalloc byte[24];

    ReadOnlySpan<byte> remaining = input;
    while (!remaining.IsEmpty)
    {
        int newline = remaining.IndexOf((byte)'\n');
        ReadOnlySpan<byte> line = newline < 0 ? remaining : remaining[..newline];
        remaining = newline < 0 ? [] : remaining[(newline + 1)..];

        if (line.Trim(" \t"u8).IsEmpty)
        {
            continue;
        }

        if (Evaluator.TryEvaluate(line, out long value) && Utf8Formatter.TryFormat(value, number, out int written))
        {
            number[written++] = (byte)'\n';
            stdout.Write(number[..written]);
        }
        else
        {
            stdout.Write(errorLine);
        }
    }
}
