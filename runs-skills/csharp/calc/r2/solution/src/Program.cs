using Calc;

// Deeply nested expressions recurse once per level; run on a thread with a generous stack.
const int StackSize = 512 * 1024 * 1024;
var worker = new Thread(Run, StackSize);
worker.Start();
worker.Join();
return 0;

static void Run()
{
    using Stream input = Console.OpenStandardInput();
    using Stream output = Console.OpenStandardOutput();
    LineProcessor.Process(input, output);
}
