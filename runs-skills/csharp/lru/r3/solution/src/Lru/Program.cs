using System.Globalization;
using System.Text;
using Lru;

using var input = new StreamReader(Console.OpenStandardInput(), Encoding.ASCII, false, 1 << 16);
using var output = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false), 1 << 16)
{
    NewLine = "\n",
};

string? header = input.ReadLine();
if (header is null || !int.TryParse(header.AsSpan().Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out int capacity))
{
    return;
}

var cache = new LruCache<string, string>(capacity, StringComparer.Ordinal);

while (input.ReadLine() is { } line)
{
    ReadOnlySpan<char> rest = line.AsSpan().TrimEnd('\r');
    ReadOnlySpan<char> command = NextToken(ref rest);

    switch (command)
    {
        case "SET":
            string key = NextToken(ref rest).ToString();
            cache.Set(key, NextToken(ref rest).ToString());
            break;
        case "GET":
            output.WriteLine(cache.TryGet(NextToken(ref rest).ToString(), out string? value) ? value : "NULL");
            break;
        case "DEL":
            output.WriteLine(cache.Remove(NextToken(ref rest).ToString()) ? "1" : "0");
            break;
        case "SIZE":
            output.WriteLine(cache.Count.ToString(CultureInfo.InvariantCulture));
            break;
        default:
            break; // blank or unrecognized lines are ignored
    }
}

static ReadOnlySpan<char> NextToken(ref ReadOnlySpan<char> rest)
{
    int space = rest.IndexOf(' ');
    ReadOnlySpan<char> token;
    if (space < 0)
    {
        token = rest;
        rest = [];
    }
    else
    {
        token = rest[..space];
        rest = rest[(space + 1)..];
    }

    return token;
}
