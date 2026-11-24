using System.Runtime.InteropServices;
using System.Text;

namespace WordFreq;

/// <summary>
/// Counts word frequencies in a byte stream. A word is a maximal run of ASCII letters,
/// folded to lowercase; every other byte is a separator.
/// </summary>
public sealed class WordCounter
{
    private readonly Dictionary<string, int> _counts = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int>.AlternateLookup<ReadOnlySpan<char>> _lookup;
    private char[] _word = new char[64];
    private int _wordLength;

    public WordCounter() => _lookup = _counts.GetAlternateLookup<ReadOnlySpan<char>>();

    public IReadOnlyDictionary<string, int> Counts => _counts;

    /// <summary>Feeds a chunk of input. Words may span chunk boundaries.</summary>
    public void Add(ReadOnlySpan<byte> chunk)
    {
        foreach (byte b in chunk)
        {
            // Setting bit 0x20 maps 'A'..'Z' onto 'a'..'z' and leaves 'a'..'z' unchanged.
            int lower = b | 0x20;
            if ((uint)(lower - 'a') <= 'z' - 'a')
            {
                if (_wordLength == _word.Length)
                {
                    Array.Resize(ref _word, _word.Length * 2);
                }
                _word[_wordLength++] = (char)lower;
            }
            else if (_wordLength > 0)
            {
                FlushWord();
            }
        }
    }

    /// <summary>Signals end of input, counting any word still in progress.</summary>
    public void Complete()
    {
        if (_wordLength > 0)
        {
            FlushWord();
        }
    }

    private void FlushWord()
    {
        ref int count = ref CollectionsMarshal.GetValueRefOrAddDefault(
            _lookup, _word.AsSpan(0, _wordLength), out _);
        count++;
        _wordLength = 0;
    }

    /// <summary>
    /// Returns up to <paramref name="limit"/> entries ordered by count descending,
    /// then by word ascending (ordinal, which equals byte order for ASCII).
    /// </summary>
    public List<KeyValuePair<string, int>> Top(int limit)
    {
        var top = new List<KeyValuePair<string, int>>(limit + 1);
        if (limit <= 0)
        {
            return top;
        }

        foreach (var entry in _counts)
        {
            if (top.Count == limit && Compare(entry, top[^1]) >= 0)
            {
                continue;
            }

            int index = top.Count;
            while (index > 0 && Compare(entry, top[index - 1]) < 0)
            {
                index--;
            }
            top.Insert(index, entry);

            if (top.Count > limit)
            {
                top.RemoveAt(top.Count - 1);
            }
        }
        return top;
    }

    private static int Compare(KeyValuePair<string, int> x, KeyValuePair<string, int> y)
    {
        int byCount = y.Value.CompareTo(x.Value);
        return byCount != 0 ? byCount : string.CompareOrdinal(x.Key, y.Key);
    }
}

public static class Program
{
    private const int TopCount = 10;
    private const int BufferSize = 1 << 16;

    public static int Main()
    {
        var counter = new WordCounter();

        using (Stream input = Console.OpenStandardInput())
        {
            byte[] buffer = new byte[BufferSize];
            int read;
            while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
            {
                counter.Add(buffer.AsSpan(0, read));
            }
        }
        counter.Complete();

        var output = new StringBuilder();
        foreach (var (word, count) in counter.Top(TopCount))
        {
            output.Append(count).Append(' ').Append(word).Append('\n');
        }

        using Stream stdout = Console.OpenStandardOutput();
        stdout.Write(Encoding.ASCII.GetBytes(output.ToString()));
        return 0;
    }
}
