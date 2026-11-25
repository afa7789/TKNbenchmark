using System.Globalization;
using System.Text;

namespace Lru;

internal static class Program
{
    private const string Missing = "NULL";

    private static int Main()
    {
        using var input = new StreamReader(
            Console.OpenStandardInput(), Encoding.ASCII, detectEncodingFromByteOrderMarks: false, bufferSize: 1 << 16);
        using var output = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false), bufferSize: 1 << 16)
        {
            AutoFlush = false,
            NewLine = "\n",
        };

        string? header = input.ReadLine();
        if (header is null)
        {
            return 0;
        }

        int capacity = int.Parse(header.AsSpan().Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture);
        var cache = new LruCache<string, string>(capacity, StringComparer.Ordinal);

        while (input.ReadLine() is { } line)
        {
            Execute(cache, line.AsSpan().TrimEnd('\r'), output);
        }

        output.Flush();
        return 0;
    }

    private static void Execute(LruCache<string, string> cache, ReadOnlySpan<char> line, TextWriter output)
    {
        int split = line.IndexOf(' ');
        ReadOnlySpan<char> command = split < 0 ? line : line[..split];
        ReadOnlySpan<char> args = split < 0 ? [] : line[(split + 1)..];

        switch (command)
        {
            case "SET":
            {
                int sep = args.IndexOf(' ');
                if (sep < 0)
                {
                    return;
                }

                cache.Set(args[..sep].ToString(), args[(sep + 1)..].ToString());
                break;
            }

            case "GET":
                output.WriteLine(cache.TryGet(args, out string? value) ? value : Missing);
                break;

            case "DEL":
                output.WriteLine(cache.Remove(args) ? '1' : '0');
                break;

            case "SIZE":
                output.WriteLine(cache.Count);
                break;

            default:
                // Blank or unrecognised lines produce no output.
                break;
        }
    }
}
