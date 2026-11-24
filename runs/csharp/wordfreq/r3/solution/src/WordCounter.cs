namespace WordFreq;

/// <summary>
/// Counts case-folded words, where a word is a maximal run of ASCII letters.
/// Every other byte acts as a separator, so arbitrary (non-UTF-8) input is fine.
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
        char[] word = new char[64];
        int wordLength = 0;

        int read;
        while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
        {
            foreach (byte b in buffer.AsSpan(0, read))
            {
                // Setting bit 0x20 maps 'A'-'Z' onto 'a'-'z' and leaves 'a'-'z' unchanged.
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

    private static void Increment(
        Dictionary<string, int>.AlternateLookup<ReadOnlySpan<char>> lookup,
        ReadOnlySpan<char> word)
    {
        lookup.TryGetValue(word, out int current);
        lookup[word] = current + 1;
    }
}
