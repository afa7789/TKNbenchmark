using System.Text;

namespace WordFreq;

/// <summary>
/// Reads standard input and prints the most frequent ASCII-letter words.
/// </summary>
public static class Program
{
    private const int TopCount = 10;

    public static int Main()
    {
        using Stream input = Console.OpenStandardInput();
        Dictionary<string, int> counts = WordCounter.Count(input);

        using var output = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false));
        output.NewLine = "\n";

        var top = counts
            .OrderByDescending(pair => pair.Value)
            .ThenBy(pair => pair.Key, StringComparer.Ordinal)
            .Take(TopCount);

        foreach (var (word, count) in top)
        {
            output.Write(count);
            output.Write(' ');
            output.WriteLine(word);
        }

        return 0;
    }
}
