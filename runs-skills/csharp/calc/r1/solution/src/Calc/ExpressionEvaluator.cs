namespace Calc;

/// <summary>
/// Evaluates 64-bit signed integer expressions with <c>+ - * / %</c>, unary minus and parentheses.
/// </summary>
/// <remarks>
/// Uses an iterative operator-precedence (shunting-yard) parser so that deeply nested input cannot
/// exhaust the call stack. Instances reuse their internal stacks and are not thread-safe.
/// </remarks>
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

    private readonly Stack<long> _values = new();
    private readonly Stack<Op> _operators = new();

    /// <summary>Evaluates one ASCII expression; returns false on any syntax or arithmetic error.</summary>
    public bool TryEvaluate(ReadOnlySpan<byte> expression, out long result)
    {
        _values.Clear();
        _operators.Clear();
        result = 0;

        bool expectOperand = true;
        int i = 0;
        while (i < expression.Length)
        {
            byte c = expression[i];
            if (c is (byte)' ' or (byte)'\t')
            {
                i++;
                continue;
            }

            if (expectOperand)
            {
                if (char.IsAsciiDigit((char)c))
                {
                    if (!TryParseNumber(expression, ref i, out long number))
                    {
                        return false;
                    }

                    _values.Push(number);
                    expectOperand = false;
                    continue;
                }

                switch (c)
                {
                    case (byte)'-':
                        _operators.Push(Op.Negate);
                        break;
                    case (byte)'(':
                        _operators.Push(Op.OpenParen);
                        break;
                    default:
                        return false;
                }

                i++;
                continue;
            }

            if (c == (byte)')')
            {
                if (!ReduceUntilOpenParen())
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

            // Left associativity: reduce every pending operator that binds at least as tightly.
            int precedence = Precedence(op);
            while (_operators.TryPeek(out Op top) && top != Op.OpenParen && Precedence(top) >= precedence)
            {
                if (!Reduce(_operators.Pop()))
                {
                    return false;
                }
            }

            _operators.Push(op);
            expectOperand = true;
            i++;
        }

        if (expectOperand)
        {
            return false;
        }

        while (_operators.TryPop(out Op pending))
        {
            if (pending == Op.OpenParen || !Reduce(pending))
            {
                return false;
            }
        }

        result = _values.Pop();
        return true;
    }

    private bool ReduceUntilOpenParen()
    {
        while (_operators.TryPop(out Op op))
        {
            if (op == Op.OpenParen)
            {
                return true;
            }

            if (!Reduce(op))
            {
                return false;
            }
        }

        return false;
    }

    private bool Reduce(Op op)
    {
        if (op == Op.Negate)
        {
            long operand = _values.Pop();
            if (operand == long.MinValue)
            {
                return false;
            }

            _values.Push(-operand);
            return true;
        }

        long right = _values.Pop();
        long left = _values.Pop();
        if (!Checked.TryApply(op, left, right, out long value))
        {
            return false;
        }

        _values.Push(value);
        return true;
    }

    private static int Precedence(Op op) => op switch
    {
        Op.Add or Op.Subtract => 1,
        Op.Multiply or Op.Divide or Op.Remainder => 2,
        Op.Negate => 3,
        _ => 0,
    };

    private static bool TryParseNumber(ReadOnlySpan<byte> s, ref int index, out long number)
    {
        number = 0;
        bool overflow = false;
        while (index < s.Length && char.IsAsciiDigit((char)s[index]))
        {
            int digit = s[index] - '0';
            if (number > (long.MaxValue - digit) / 10)
            {
                overflow = true;
            }
            else
            {
                number = (number * 10) + digit;
            }

            index++;
        }

        return !overflow;
    }

    private static class Checked
    {
        public static bool TryApply(Op op, long a, long b, out long result)
        {
            result = 0;
            switch (op)
            {
                case Op.Add:
                    result = unchecked(a + b);
                    return ((a ^ result) & (b ^ result)) >= 0;
                case Op.Subtract:
                    result = unchecked(a - b);
                    return ((a ^ b) & (a ^ result)) >= 0;
                case Op.Multiply:
                    Int128 product = (Int128)a * b;
                    if (product < long.MinValue || product > long.MaxValue)
                    {
                        return false;
                    }

                    result = (long)product;
                    return true;
                case Op.Divide:
                    if (b == 0 || (a == long.MinValue && b == -1))
                    {
                        return false;
                    }

                    result = a / b;
                    return true;
                case Op.Remainder:
                    if (b == 0)
                    {
                        return false;
                    }

                    // MinValue % -1 is mathematically 0 but faults in hardware division.
                    result = b == -1 ? 0 : a % b;
                    return true;
                default:
                    return false;
            }
        }
    }
}
