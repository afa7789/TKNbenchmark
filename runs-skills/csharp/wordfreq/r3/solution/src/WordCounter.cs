using System.Runtime.InteropServices;

namespace WordFreq;

/// <summary>
/// Counts case-folded words, where a word is a maximal run of ASCII letters.
/// Input is fed as raw bytes in arbitrary chunks; words may span chunk boundaries.
/// </summary>
public sealed class WordCounter
{
    private readonly Dictionary<string, int> _counts = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int>.AlternateLookup<ReadOnlySpan<char>> _lookup;
    private char[] _word = new char[64];
    private int _length;

    public WordCounter() => _lookup = _counts.GetAlternateLookup<ReadOnlySpan<char>>();

    /// <summary>Processes the next chunk of input bytes.</summary>
    public void Add(ReadOnlySpan<byte> chunk)
    {
        foreach (byte b in chunk)
        {
            // Setting bit 0x20 maps 'A'-'Z' onto 'a'-'z' and leaves lowercase unchanged.
            uint lower = (uint)(b | 0x20);
            if (lower - 'a' <= 'z' - 'a')
            {
                if (_length == _word.Length)
                {
                    Array.Resize(ref _word, _word.Length * 2);
                }
                _word[_length++] = (char)lower;
            }
            else if (_length > 0)
            {
                FlushWord();
            }
        }
    }

    /// <summary>Finishes any pending word and returns the <paramref name="limit"/> most frequent words.</summary>
    public IReadOnlyList<KeyValuePair<string, int>> Top(int limit)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(limit);
        if (_length > 0)
        {
            FlushWord();
        }

        var entries = _counts.ToArray();
        Array.Sort(entries, static (x, y) =>
        {
            int byCount = y.Value.CompareTo(x.Value);
            return byCount != 0 ? byCount : string.CompareOrdinal(x.Key, y.Key);
        });
        return entries.Length <= limit ? entries : entries[..limit];
    }

    private void FlushWord()
    {
        ref int count = ref CollectionsMarshal.GetValueRefOrAddDefault(_lookup, _word.AsSpan(0, _length), out _);
        count++;
        _length = 0;
    }
}
