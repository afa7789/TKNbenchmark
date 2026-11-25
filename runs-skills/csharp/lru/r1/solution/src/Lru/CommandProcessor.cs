namespace Lru;

/// <summary>Parses one command line and applies it to an <see cref="LruCache"/>.</summary>
public static class CommandProcessor
{
    public static void Execute(LruCache cache, ReadOnlySpan<char> line, TextWriter output)
    {
        ArgumentNullException.ThrowIfNull(cache);
        ArgumentNullException.ThrowIfNull(output);

        int space = line.IndexOf(' ');
        ReadOnlySpan<char> command = space < 0 ? line : line[..space];
        ReadOnlySpan<char> args = space < 0 ? [] : line[(space + 1)..];

        switch (command)
        {
            case "SET":
                int split = args.IndexOf(' ');
                if (split > 0)
                {
                    cache.Set(args[..split], args[(split + 1)..]);
                }

                break;
            case "GET":
                output.WriteLine(cache.TryGet(args, out string value) ? value : "NULL");
                break;
            case "DEL":
                output.WriteLine(cache.Remove(args) ? "1" : "0");
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
