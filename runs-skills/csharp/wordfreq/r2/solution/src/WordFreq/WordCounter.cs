using System.Runtime.InteropServices;

namespace WordFreq;

/// <summary>
/// Counts case-insensitive words, where a word is a maximal run of ASCII letters.
/// Every other byte is treated as a separator.
/// </summary>
public sealed class WordCounter
{
    private const int BufferSize = 1 << 16;

    private readonly Dictionary<string, int> _counts = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int>.AlternateLookup<ReadOnlySpan<char>> _lookup;

    // Holds the (lowercased) letters of the word currently being scanned; it may span reads.
    private char[] _word = new char[64];
    private int _wordLength;

    private WordCounter() => _lookup = _counts.GetAlternateLookup<ReadOnlySpan<char>>();

    /// <summary>Reads <paramref name="input"/> to the end and counts every word in it.</summary>
    public static WordCounter Count(Stream input)
    {
        ArgumentNullException.ThrowIfNull(input);

        var counter = new WordCounter();
        byte[] buffer = new byte[BufferSize];
        int read;
        while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
        {
            counter.Feed(buffer.AsSpan(0, read));
        }

        counter.FlushWord();
        return counter;
    }

    /// <summary>
    /// Returns up to <paramref name="limit"/> words ordered by count descending,
    /// then by word ascending (ordinal, which equals byte order for ASCII).
    /// </summary>
    public IReadOnlyList<(string Word, int Count)> Top(int limit)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(limit);

        var top = new List<(string Word, int Count)>(limit + 1);
        foreach (var (word, count) in _counts)
        {
            if (top.Count == limit && !Precedes(word, count, top[^1]))
            {
                continue;
            }

            int index = top.Count;
            while (index > 0 && Precedes(word, count, top[index - 1]))
            {
                index--;
            }

            top.Insert(index, (word, count));
            if (top.Count > limit)
            {
                top.RemoveAt(top.Count - 1);
            }
        }

        return top;
    }

    private static bool Precedes(string word, int count, (string Word, int Count) other) =>
        count != other.Count
            ? count > other.Count
            : string.CompareOrdinal(word, other.Word) < 0;

    private void Feed(ReadOnlySpan<byte> chunk)
    {
        for (int i = 0; i < chunk.Length; i++)
        {
            // Setting bit 0x20 maps 'A'..'Z' onto 'a'..'z' and leaves 'a'..'z' unchanged.
            int lower = chunk[i] | 0x20;
            if ((uint)(lower - 'a') <= 'z' - 'a')
            {
                Append((char)lower);
            }
            else if (_wordLength > 0)
            {
                FlushWord();
            }
        }
    }

    private void Append(char c)
    {
        if (_wordLength == _word.Length)
        {
            Array.Resize(ref _word, _word.Length * 2);
        }

        _word[_wordLength++] = c;
    }

    private void FlushWord()
    {
        if (_wordLength == 0)
        {
            return;
        }

        ref int count = ref CollectionsMarshal.GetValueRefOrAddDefault(
            _lookup, _word.AsSpan(0, _wordLength), out _);
        count++;
        _wordLength = 0;
    }
}
