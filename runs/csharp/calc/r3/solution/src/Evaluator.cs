namespace Calc;

/// <summary>
/// Recursive-descent evaluator for 64-bit signed integer expressions.
/// </summary>
/// <remarks>
/// Grammar:
/// <code>
/// expr    := term    (('+' | '-') term)*
/// term    := unary   (('*' | '/' | '%') unary)*
/// unary   := '-' unary | primary
/// primary := NUMBER | '(' expr ')'
/// NUMBER  := [0-9]+
/// </code>
/// Every failure (syntax, division by zero, overflow) is reported uniformly
/// through a <c>false</c> return value rather than exceptions, keeping the
/// hot path allocation- and throw-free.
/// </remarks>
public ref struct Evaluator
{
    private readonly ReadOnlySpan<byte> _input;
    private int _pos;

    private Evaluator(ReadOnlySpan<byte> input)
    {
        _input = input;
        _pos = 0;
    }

    /// <summary>Evaluates a single expression line (without the trailing newline).</summary>
    public static bool TryEvaluate(ReadOnlySpan<byte> line, out long value)
    {
        var evaluator = new Evaluator(line);
        if (!evaluator.ParseExpr(out value))
        {
            return false;
        }

        evaluator.SkipWhitespace();
        return evaluator._pos == evaluator._input.Length;
    }

    /// <summary>True when the line contains only spaces and tabs.</summary>
    public static bool IsBlank(ReadOnlySpan<byte> line)
    {
        foreach (byte b in line)
        {
            if (!IsWhitespace(b))
            {
                return false;
            }
        }

        return true;
    }

    private static bool IsWhitespace(byte b) => b is (byte)' ' or (byte)'\t';

    private void SkipWhitespace()
    {
        while (_pos < _input.Length && IsWhitespace(_input[_pos]))
        {
            _pos++;
        }
    }

    /// <summary>Skips whitespace and returns the next byte, or -1 at end of input.</summary>
    private int Peek()
    {
        SkipWhitespace();
        return _pos < _input.Length ? _input[_pos] : -1;
    }

    private bool ParseExpr(out long value)
    {
        if (!ParseTerm(out value))
        {
            return false;
        }

        while (true)
        {
            int op = Peek();
            if (op is not ('+' or '-'))
            {
                return true;
            }

            _pos++;
            if (!ParseTerm(out long rhs))
            {
                return false;
            }

            bool ok = op == '+'
                ? Checked.TryAdd(value, rhs, out value)
                : Checked.TrySubtract(value, rhs, out value);
            if (!ok)
            {
                return false;
            }
        }
    }

    private bool ParseTerm(out long value)
    {
        if (!ParseUnary(out value))
        {
            return false;
        }

        while (true)
        {
            int op = Peek();
            if (op is not ('*' or '/' or '%'))
            {
                return true;
            }

            _pos++;
            if (!ParseUnary(out long rhs))
            {
                return false;
            }

            bool ok = op switch
            {
                '*' => Checked.TryMultiply(value, rhs, out value),
                '/' => Checked.TryDivide(value, rhs, out value),
                _ => Checked.TryRemainder(value, rhs, out value),
            };
            if (!ok)
            {
                return false;
            }
        }
    }

    private bool ParseUnary(out long value)
    {
        // Count consecutive minus signs iteratively so long chains like "-----5"
        // do not consume stack proportional to their length.
        int negations = 0;
        while (Peek() == '-')
        {
            _pos++;
            negations++;
        }

        if (!ParsePrimary(out value))
        {
            return false;
        }

        // Negating an even number of times is the identity unless the value is
        // long.MinValue, whose first negation already overflows.
        if (negations == 0)
        {
            return true;
        }

        if (value == long.MinValue)
        {
            return false;
        }

        if ((negations & 1) == 1)
        {
            value = -value;
        }

        return true;
    }

    private bool ParsePrimary(out long value)
    {
        int c = Peek();
        if (c == '(')
        {
            _pos++;
            if (!ParseExpr(out value) || Peek() != ')')
            {
                return false;
            }

            _pos++;
            return true;
        }

        if (c is >= '0' and <= '9')
        {
            return ParseNumber(out value);
        }

        value = 0;
        return false;
    }

    private bool ParseNumber(out long value)
    {
        long result = 0;
        bool overflow = false;
        while (_pos < _input.Length && _input[_pos] is >= (byte)'0' and <= (byte)'9')
        {
            int digit = _input[_pos] - '0';
            if (!overflow && (result > (long.MaxValue - digit) / 10))
            {
                overflow = true;
            }

            if (!overflow)
            {
                result = (result * 10) + digit;
            }

            _pos++;
        }

        value = result;
        return !overflow;
    }
}
