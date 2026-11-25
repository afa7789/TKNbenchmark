using System.Buffers;

namespace WordFreq;

/// <summary>
/// Counts case-insensitive words, where a word is a maximal run of ASCII letters.
/// Input is fed incrementally as raw bytes; words may span chunk boundaries.
/// </summary>
public sealed class WordCounter
{
    private static readonly SearchValues<byte> Letters =
        SearchValues.Create("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"u8);

    private readonly Dictionary<string, int> _counts = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int>.AlternateLookup<ReadOnlySpan<char>> _lookup;
    private char[] _word = new char[64];
    private int _wordLength;

    public WordCounter() => _lookup = _counts.GetAlternateLookup<ReadOnlySpan<char>>();

    /// <summary>Processes the next chunk of input.</summary>
    public void Add(ReadOnlySpan<byte> chunk)
    {
        while (!chunk.IsEmpty)
        {
            if (_wordLength == 0)
            {
                int start = chunk.IndexOfAny(Letters);
                if (start < 0)
                {
                    return;
                }
                chunk = chunk[start..];
            }

            int end = chunk.IndexOfAnyExcept(Letters);
            if (end < 0)
            {
                Append(chunk);
                return;
            }

            Append(chunk[..end]);
            FlushWord();
            chunk = chunk[end..];
        }
    }

    /// <summary>Signals end of input, counting any word still in progress.</summary>
    public void Complete() => FlushWord();

    /// <summary>Returns the most frequent words, by count descending then word ascending (ordinal).</summary>
    public IReadOnlyList<KeyValuePair<string, int>> Top(int n)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(n);
        return _counts
            .OrderByDescending(static kv => kv.Value)
            .ThenBy(static kv => kv.Key, StringComparer.Ordinal)
            .Take(n)
            .ToList();
    }

    private void Append(ReadOnlySpan<byte> letters)
    {
        int required = _wordLength + letters.Length;
        if (required > _word.Length)
        {
            Array.Resize(ref _word, Math.Max(required, _word.Length * 2));
        }

        Span<char> target = _word.AsSpan(_wordLength, letters.Length);
        for (int i = 0; i < letters.Length; i++)
        {
            // ASCII letters only: setting bit 0x20 lowercases.
            target[i] = (char)(letters[i] | 0x20);
        }
        _wordLength = required;
    }

    private void FlushWord()
    {
        if (_wordLength == 0)
        {
            return;
        }

        ReadOnlySpan<char> word = _word.AsSpan(0, _wordLength);
        ref int count = ref System.Runtime.InteropServices.CollectionsMarshal.GetValueRefOrAddDefault(_lookup, word, out _);
        count++;
        _wordLength = 0;
    }
}
