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
counter.Complete();

var output = new StringBuilder();
foreach (var (word, count) in counter.Top(TopCount))
{
    output.Append(count.ToString(CultureInfo.InvariantCulture)).Append(' ').Append(word).Append('\n');
}

using Stream stdout = Console.OpenStandardOutput();
stdout.Write(Encoding.ASCII.GetBytes(output.ToString()));
