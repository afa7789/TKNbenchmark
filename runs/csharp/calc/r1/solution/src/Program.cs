using System.Text;
using Calc;

using var stdin = Console.OpenStandardInput();
using var stdout = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false), 1 << 16)
{
    AutoFlush = false,
    NewLine = "\n",
};

LineProcessor.Run(stdin, stdout);
stdout.Flush();
return 0;
