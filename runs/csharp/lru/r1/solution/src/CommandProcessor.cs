namespace Lru;

/// <summary>Parses textual cache commands and applies them to an <see cref="LruCache{TKey, TValue}"/>.</summary>
public sealed class CommandProcessor(LruCache<string, string> cache, TextWriter output)
{
    private const string Missing = "NULL";

    /// <summary>Executes a single command line. Blank or malformed lines are ignored.</summary>
    public void Execute(string line)
    {
        ReadOnlySpan<char> rest = line.AsSpan().TrimEnd('\r');
        ReadOnlySpan<char> command = NextToken(ref rest);

        switch (command)
        {
            case "SET":
            {
                ReadOnlySpan<char> key = NextToken(ref rest);
                ReadOnlySpan<char> value = NextToken(ref rest);
                if (!key.IsEmpty && !value.IsEmpty)
                {
                    cache.Set(key.ToString(), value.ToString());
                }

                break;
            }

            case "GET":
            {
                ReadOnlySpan<char> key = NextToken(ref rest);
                if (!key.IsEmpty)
                {
                    output.WriteLine(cache.TryGet(key.ToString(), out string? value) ? value : Missing);
                }

                break;
            }

            case "DEL":
            {
                ReadOnlySpan<char> key = NextToken(ref rest);
                if (!key.IsEmpty)
                {
                    output.WriteLine(cache.Remove(key.ToString()) ? '1' : '0');
                }

                break;
            }

            case "SIZE":
                output.WriteLine(cache.Count);
                break;
        }
    }

    private static ReadOnlySpan<char> NextToken(ref ReadOnlySpan<char> text)
    {
        text = text.TrimStart(' ');
        int end = text.IndexOf(' ');
        if (end < 0)
        {
            ReadOnlySpan<char> last = text;
            text = default;
            return last;
        }

        ReadOnlySpan<char> token = text[..end];
        text = text[(end + 1)..];
        return token;
    }
}
