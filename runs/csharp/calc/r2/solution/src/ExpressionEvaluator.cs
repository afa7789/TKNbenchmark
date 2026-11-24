namespace Calc;

/// <summary>
/// Evaluates signed 64-bit integer expressions:
/// <code>
/// expr    := term    (('+' | '-') term)*
/// term    := unary   (('*' | '/' | '%') unary)*
/// unary   := '-' unary | primary
/// primary := NUMBER | '(' expr ')'
/// </code>
/// Parsing is iterative (operator-precedence), so arbitrarily deep nesting cannot overflow the call stack.
/// Instances reuse their internal stacks and are not thread-safe.
/// </summary>
public sealed class ExpressionEvaluator
{
    private enum Op : byte
    {
        OpenParen,
        Add,
        Subtract,
        Multiply,
        Divide,
        Remainder,
        Negate,
    }

    private readonly Stack<long> _operands = new();
    private readonly Stack<Op> _operators = new();

    public static bool IsBlank(ReadOnlySpan<byte> line) => line.IndexOfAnyExcept((byte)' ', (byte)'\t') < 0;

    /// <summary>
    /// Evaluates <paramref name="line"/>. Returns false on a syntax error, division by zero, or overflow.
    /// </summary>
    public bool TryEvaluate(ReadOnlySpan<byte> line, out long result)
    {
        _operands.Clear();
        _operators.Clear();
        result = 0;

        int pos = 0;
        bool expectOperand = true;

        while (true)
        {
            pos = SkipWhitespace(line, pos);
            if (pos == line.Length)
            {
                break;
            }

            byte c = line[pos];
            if (expectOperand)
            {
                switch (c)
                {
                    case (byte)'-':
                        _operators.Push(Op.Negate);
                        pos++;
                        break;
                    case (byte)'(':
                        _operators.Push(Op.OpenParen);
                        pos++;
                        break;
                    case >= (byte)'0' and <= (byte)'9':
                        if (!TryParseNumber(line, ref pos, out long literal))
                        {
                            return false;
                        }

                        _operands.Push(literal);
                        expectOperand = false;
                        break;
                    default:
                        return false;
                }
            }
            else if (c == (byte)')')
            {
                if (!ReduceUntilOpenParen())
                {
                    return false;
                }

                pos++;
            }
            else
            {
                Op? binary = c switch
                {
                    (byte)'+' => Op.Add,
                    (byte)'-' => Op.Subtract,
                    (byte)'*' => Op.Multiply,
                    (byte)'/' => Op.Divide,
                    (byte)'%' => Op.Remainder,
                    _ => null,
                };
                if (binary is not { } op)
                {
                    return false;
                }

                // Left associativity: reduce everything that binds at least as tightly.
                int precedence = Precedence(op);
                while (_operators.TryPeek(out Op top) && top != Op.OpenParen && Precedence(top) >= precedence)
                {
                    if (!Reduce())
                    {
                        return false;
                    }
                }

                _operators.Push(op);
                expectOperand = true;
                pos++;
            }
        }

        if (expectOperand)
        {
            return false; // Empty input or a trailing operator.
        }

        while (_operators.Count > 0)
        {
            if (_operators.Peek() == Op.OpenParen || !Reduce())
            {
                return false;
            }
        }

        result = _operands.Pop();
        return true;
    }

    private static int SkipWhitespace(ReadOnlySpan<byte> line, int pos)
    {
        int offset = line[pos..].IndexOfAnyExcept((byte)' ', (byte)'\t');
        return offset < 0 ? line.Length : pos + offset;
    }

    private static bool TryParseNumber(ReadOnlySpan<byte> line, ref int pos, out long value)
    {
        value = 0;
        while (pos < line.Length && line[pos] is >= (byte)'0' and <= (byte)'9')
        {
            int digit = line[pos] - '0';
            if (value > (long.MaxValue - digit) / 10)
            {
                return false;
            }

            value = value * 10 + digit;
            pos++;
        }

        return true;
    }

    private static int Precedence(Op op) => op switch
    {
        Op.Add or Op.Subtract => 1,
        Op.Multiply or Op.Divide or Op.Remainder => 2,
        Op.Negate => 3,
        _ => 0,
    };

    private bool ReduceUntilOpenParen()
    {
        while (_operators.TryPeek(out Op top))
        {
            if (top == Op.OpenParen)
            {
                _operators.Pop();
                return true;
            }

            if (!Reduce())
            {
                return false;
            }
        }

        return false; // Unmatched ')'.
    }

    private bool Reduce()
    {
        Op op = _operators.Pop();
        long right = _operands.Pop();

        if (op == Op.Negate)
        {
            if (right == long.MinValue)
            {
                return false;
            }

            _operands.Push(-right);
            return true;
        }

        long left = _operands.Pop();
        if (!TryApply(op, left, right, out long value))
        {
            return false;
        }

        _operands.Push(value);
        return true;
    }

    private static bool TryApply(Op op, long left, long right, out long value)
    {
        switch (op)
        {
            case Op.Add:
                value = unchecked(left + right);
                return ((left ^ value) & (right ^ value)) >= 0;
            case Op.Subtract:
                value = unchecked(left - right);
                return ((left ^ right) & (left ^ value)) >= 0;
            case Op.Multiply:
                long high = Math.BigMul(left, right, out value);
                return high == (value >> 63);
            case Op.Divide:
                value = 0;
                if (right == 0 || (left == long.MinValue && right == -1))
                {
                    return false;
                }

                value = left / right;
                return true;
            case Op.Remainder:
                value = 0;
                if (right == 0)
                {
                    return false;
                }

                value = right == -1 ? 0 : left % right;
                return true;
            default:
                throw new ArgumentOutOfRangeException(nameof(op), op, "Not a binary operator.");
        }
    }
}
