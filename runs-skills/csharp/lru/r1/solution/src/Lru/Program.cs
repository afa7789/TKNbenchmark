using System.Globalization;
using System.Text;
using Lru;

const int BufferSize = 1 << 16;

var encoding = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);
using var input = new StreamReader(Console.OpenStandardInput(), encoding, detectEncodingFromByteOrderMarks: false, BufferSize);
using var output = new StreamWriter(Console.OpenStandardOutput(), encoding, BufferSize) { AutoFlush = false, NewLine = "\n" };

string? header = input.ReadLine();
if (header is null || !int.TryParse(header.AsSpan().Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out int capacity) || capacity < 1)
{
    return 0;
}

var cache = new LruCache(capacity);
string? line;
while ((line = input.ReadLine()) is not null)
{
    CommandProcessor.Execute(cache, line.AsSpan().TrimEnd('\r'), output);
}

output.Flush();
return 0;
