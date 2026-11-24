using System.Text;
using WordFreq;

using Stream input = Console.OpenStandardInput();
Dictionary<string, int> counts = WordCounter.Count(input);

var output = new StringBuilder();
foreach ((string word, int count) in WordCounter.Top(counts, 10))
{
    output.Append(count).Append(' ').Append(word).Append('\n');
}

using Stream stdout = Console.OpenStandardOutput();
stdout.Write(Encoding.ASCII.GetBytes(output.ToString()));
return 0;
