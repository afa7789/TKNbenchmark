using System.Globalization;
using System.Text;

namespace Lru;

public static class Program
{
    private const int BufferSize = 1 << 16;

    public static int Main()
    {
        using var input = new StreamReader(
            Console.OpenStandardInput(), new UTF8Encoding(false), false, BufferSize);
        using var output = new StreamWriter(
            Console.OpenStandardOutput(), new UTF8Encoding(false), BufferSize)
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
        var cache = new LruCache(capacity);

        string? line;
        while ((line = input.ReadLine()) is not null)
        {
            Execute(cache, line.AsSpan().TrimEnd('\r'), output);
        }

        output.Flush();
        return 0;
    }

    private static void Execute(LruCache cache, ReadOnlySpan<char> line, TextWriter output)
    {
        int firstSpace = line.IndexOf(' ');
        ReadOnlySpan<char> command = firstSpace < 0 ? line : line[..firstSpace];
        ReadOnlySpan<char> args = firstSpace < 0 ? [] : line[(firstSpace + 1)..];

        switch (command)
        {
            case "SET":
            {
                int split = args.IndexOf(' ');
                if (split > 0)
                {
                    cache.Set(args[..split], args[(split + 1)..]);
                }

                break;
            }

            case "GET":
                output.WriteLine(cache.TryGet(args, out string value) ? value : "NULL");
                break;

            case "DEL":
                output.WriteLine(cache.Remove(args) ? "1" : "0");
                break;

            case "SIZE":
                output.WriteLine(cache.Count);
                break;
        }
    }
}
