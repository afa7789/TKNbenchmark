namespace WordFreq;

/// <summary>
/// Counts case-insensitive words, where a word is a maximal run of ASCII letters.
/// Every other byte is treated as a separator.
/// </summary>
public static class WordCounter
{
    private const int ReadBufferSize = 1 << 16;

    public static Dictionary<string, int> Count(Stream input)
    {
        ArgumentNullException.ThrowIfNull(input);

        var counts = new Dictionary<string, int>(StringComparer.Ordinal);
        var lookup = counts.GetAlternateLookup<ReadOnlySpan<char>>();

        byte[] buffer = new byte[ReadBufferSize];
        // Holds the lowercased current word; it can span read boundaries and grows as needed.
        char[] word = new char[256];
        int wordLength = 0;

        int read;
        while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
        {
            foreach (byte b in buffer.AsSpan(0, read))
            {
                // Setting bit 0x20 maps 'A'..'Z' onto 'a'..'z' and leaves 'a'..'z' unchanged.
                int lower = b | 0x20;
                if ((uint)(lower - 'a') <= 'z' - 'a')
                {
                    if (wordLength == word.Length)
                    {
                        Array.Resize(ref word, word.Length * 2);
                    }
                    word[wordLength++] = (char)lower;
                }
                else if (wordLength > 0)
                {
                    Increment(lookup, word.AsSpan(0, wordLength));
                    wordLength = 0;
                }
            }
        }

        if (wordLength > 0)
        {
            Increment(lookup, word.AsSpan(0, wordLength));
        }

        return counts;
    }

    /// <summary>
    /// Returns up to <paramref name="limit"/> entries ordered by count descending,
    /// then by word ascending (ordinal, which equals byte order for ASCII).
    /// </summary>
    public static List<KeyValuePair<string, int>> Top(Dictionary<string, int> counts, int limit)
    {
        ArgumentNullException.ThrowIfNull(counts);
        ArgumentOutOfRangeException.ThrowIfNegative(limit);

        return counts
            .OrderByDescending(pair => pair.Value)
            .ThenBy(pair => pair.Key, StringComparer.Ordinal)
            .Take(limit)
            .ToList();
    }

    private static void Increment(
        Dictionary<string, int>.AlternateLookup<ReadOnlySpan<char>> lookup,
        ReadOnlySpan<char> word)
    {
        if (lookup.TryGetValue(word, out int count))
        {
            lookup[word] = count + 1;
        }
        else
        {
            lookup[word] = 1;
        }
    }
}
