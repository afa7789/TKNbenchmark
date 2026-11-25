using System.Globalization;
using System.Text;
using WordFreq;

const int TopCount = 10;

var counter = new WordCounter();
using (Stream input = Console.OpenStandardInput())
{
    byte[] buffer = new byte[1 << 16];
    int read;
    while ((read = input.Read(buffer)) > 0)
    {
        counter.Add(buffer.AsSpan(0, read));
    }
}

using var output = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { NewLine = "\n" };
foreach (var (word, count) in counter.Top(TopCount))
{
    output.WriteLine(string.Create(CultureInfo.InvariantCulture, $"{count} {word}"));
}
