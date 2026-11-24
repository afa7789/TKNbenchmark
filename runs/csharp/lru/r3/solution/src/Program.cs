using System.Globalization;
using System.Text;
using Lru;

using var input = new StreamReader(Console.OpenStandardInput(), Encoding.Latin1, false, 1 << 16);
using var output = new StreamWriter(Console.OpenStandardOutput(), Encoding.Latin1, 1 << 16) { AutoFlush = false };

string? header = input.ReadLine();
if (header is null || !int.TryParse(header.AsSpan().Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out int capacity) || capacity < 1)
{
    Console.Error.WriteLine("error: first line must be a positive integer capacity");
    return 1;
}

var cache = new LruCache(capacity);

while (input.ReadLine() is { } line)
{
    ReadOnlySpan<char> rest = line.AsSpan().TrimEnd('\r');
    ReadOnlySpan<char> command = NextToken(ref rest);

    switch (command)
    {
        case "SET":
        {
            ReadOnlySpan<char> key = NextToken(ref rest);
            ReadOnlySpan<char> value = NextToken(ref rest);
            cache.Set(key, value);
            break;
        }
        case "GET":
            output.Write(cache.TryGet(NextToken(ref rest), out string? cached) ? cached : "NULL");
            output.Write('\n');
            break;
        case "DEL":
            output.Write(cache.Remove(NextToken(ref rest)) ? '1' : '0');
            output.Write('\n');
            break;
        case "SIZE":
            output.Write(cache.Count);
            output.Write('\n');
            break;
        default:
            // Blank or unrecognised lines are ignored.
            break;
    }
}

output.Flush();
return 0;

static ReadOnlySpan<char> NextToken(ref ReadOnlySpan<char> rest)
{
    int space = rest.IndexOf(' ');
    ReadOnlySpan<char> token;
    if (space < 0)
    {
        token = rest;
        rest = default;
    }
    else
    {
        token = rest[..space];
        rest = rest[(space + 1)..];
    }

    return token;
}
