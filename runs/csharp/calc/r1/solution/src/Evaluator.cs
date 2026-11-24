namespace Calc;

/// <summary>
/// Evaluates 64-bit signed integer expressions:
/// <code>
/// expr    := term    (('+' | '-') term)*
/// term    := unary   (('*' | '/' | '%') unary)*
/// unary   := '-' unary | primary
/// primary := NUMBER | '(' expr ')'
/// </code>
/// Parsing is iterative (operator-precedence with explicit stacks), so arbitrarily deep
/// nesting cannot overflow the call stack.
/// </summary>
public static class Evaluator
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

    private static int Precedence(Op op) => op switch
    {
        Op.Add or Op.Subtract => 1,
        Op.Multiply or Op.Divide or Op.Remainder => 2,
        Op.Negate => 3,
        _ => 0,
    };

    /// <summary>Returns false on any syntax error, division by zero, or overflow.</summary>
    public static bool TryEvaluate(ReadOnlySpan<byte> text, out long result)
    {
        result = 0;
        var values = new Stack<long>();
        var ops = new Stack<Op>();
        bool expectOperand = true;
        int i = 0;

        while (i < text.Length)
        {
            byte c = text[i];

            if (c is (byte)' ' or (byte)'\t')
            {
                i++;
                continue;
            }

            if (expectOperand)
            {
                if (IsDigit(c))
                {
                    if (!TryParseNumber(text, ref i, out long number))
                    {
                        return false;
                    }

                    values.Push(number);
                    expectOperand = false;
                    continue;
                }

                switch (c)
                {
                    case (byte)'-':
                        ops.Push(Op.Negate);
                        break;
                    case (byte)'(':
                        ops.Push(Op.OpenParen);
                        break;
                    default:
                        return false;
                }

                i++;
                continue;
            }

            if (c == (byte)')')
            {
                while (ops.TryPeek(out Op top) && top != Op.OpenParen)
                {
                    if (!Reduce(values, ops.Pop()))
                    {
                        return false;
                    }
                }

                if (!ops.TryPop(out _))
                {
                    return false;
                }

                i++;
                continue;
            }

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

            // All binary operators are left-associative; unary minus binds tighter than any of them.
            int precedence = Precedence(op);
            while (ops.TryPeek(out Op top) && Precedence(top) >= precedence)
            {
                if (!Reduce(values, ops.Pop()))
                {
                    return false;
                }
            }

            ops.Push(op);
            expectOperand = true;
            i++;
        }

        if (expectOperand)
        {
            return false;
        }

        while (ops.TryPop(out Op op))
        {
            if (op == Op.OpenParen || !Reduce(values, op))
            {
                return false;
            }
        }

        result = values.Pop();
        return true;
    }

    private static bool IsDigit(byte c) => (uint)(c - '0') <= 9;

    private static bool TryParseNumber(ReadOnlySpan<byte> text, ref int i, out long value)
    {
        value = 0;
        for (; i < text.Length && IsDigit(text[i]); i++)
        {
            int digit = text[i] - '0';
            if (value > (long.MaxValue - digit) / 10)
            {
                return false;
            }

            value = value * 10 + digit;
        }

        return true;
    }

    private static bool Reduce(Stack<long> values, Op op)
    {
        if (op == Op.Negate)
        {
            long operand = values.Pop();
            if (operand == long.MinValue)
            {
                return false;
            }

            values.Push(-operand);
            return true;
        }

        long right = values.Pop();
        long left = values.Pop();
        if (!TryApply(op, left, right, out long value))
        {
            return false;
        }

        values.Push(value);
        return true;
    }

    private static bool TryApply(Op op, long left, long right, out long value)
    {
        value = 0;
        switch (op)
        {
            case Op.Add:
                value = unchecked(left + right);
                return ((left ^ value) & (right ^ value)) >= 0;

            case Op.Subtract:
                value = unchecked(left - right);
                return ((left ^ right) & (left ^ value)) >= 0;

            case Op.Multiply:
                Int128 product = (Int128)left * right;
                if (product < long.MinValue || product > long.MaxValue)
                {
                    return false;
                }

                value = (long)product;
                return true;

            case Op.Divide:
                if (right == 0 || (left == long.MinValue && right == -1))
                {
                    return false;
                }

                value = left / right;
                return true;

            case Op.Remainder:
                if (right == 0)
                {
                    return false;
                }

                // MinValue % -1 would trap on some platforms; mathematically it is 0.
                value = right == -1 ? 0 : left % right;
                return true;

            default:
                throw new InvalidOperationException($"Unexpected operator {op}.");
        }
    }
}
