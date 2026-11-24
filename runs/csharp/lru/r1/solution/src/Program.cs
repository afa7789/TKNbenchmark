using System.Text;

namespace Lru;

/// <summary>
/// Reads an LRU capacity followed by cache commands from standard input and writes
/// the results of each query command to standard output.
/// </summary>
public static class Program
{
    private const int BufferSize = 1 << 16;

    public static int Main()
    {
        using var input = new StreamReader(
            Console.OpenStandardInput(), Encoding.Latin1, detectEncodingFromByteOrderMarks: false, BufferSize);
        using var output = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false), BufferSize)
        {
            AutoFlush = false,
            NewLine = "\n",
        };

        string? header = ReadNonEmptyLine(input);
        if (header is null || !int.TryParse(header.AsSpan().Trim(), out int capacity) || capacity < 1)
        {
            Console.Error.WriteLine("error: first line must be a positive integer capacity");
            return 0;
        }

        var cache = new LruCache<string, string>(capacity, StringComparer.Ordinal);
        var processor = new CommandProcessor(cache, output);

        string? line;
        while ((line = input.ReadLine()) is not null)
        {
            processor.Execute(line);
        }

        output.Flush();
        return 0;
    }

    private static string? ReadNonEmptyLine(TextReader reader)
    {
        string? line;
        while ((line = reader.ReadLine()) is not null)
        {
            if (!string.IsNullOrWhiteSpace(line))
            {
                return line;
            }
        }

        return null;
    }
}
