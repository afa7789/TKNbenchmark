using WordFreq;

using Stream stdin = Console.OpenStandardInput();
WordCounter counter = WordCounter.Count(stdin);

using var stdout = new StreamWriter(Console.OpenStandardOutput()) { NewLine = "\n" };
foreach (var (word, count) in counter.Top(10))
{
    stdout.Write(count);
    stdout.Write(' ');
    stdout.WriteLine(word);
}

return 0;
