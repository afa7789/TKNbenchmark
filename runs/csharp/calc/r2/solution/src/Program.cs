using Calc;

using Stream input = Console.OpenStandardInput();
using Stream output = Console.OpenStandardOutput();

var evaluator = new ExpressionEvaluator();
var reader = new LineReader(input);
var writer = new BufferedStream(output, 1 << 16);
Span<byte> number = stackalloc byte[24];
ReadOnlySpan<byte> error = "error\n"u8;

while (reader.TryReadLine(out ReadOnlySpan<byte> line))
{
    if (ExpressionEvaluator.IsBlank(line))
    {
        continue;
    }

    if (evaluator.TryEvaluate(line, out long value) && value.TryFormat(number, out int written))
    {
        number[written] = (byte)'\n';
        writer.Write(number[..(written + 1)]);
    }
    else
    {
        writer.Write(error);
    }
}

writer.Flush();
return 0;
