using Calc;

// Deeply nested parentheses recurse through the parser, so evaluate on a
// thread whose stack is large enough for any realistically sized line.
const int StackSize = 1 << 30;

var worker = new Thread(() =>
{
    using Stream stdin = Console.OpenStandardInput();
    using Stream stdout = Console.OpenStandardOutput();
    LineProcessor.Run(stdin, stdout);
}, StackSize);

worker.Start();
worker.Join();
return 0;
