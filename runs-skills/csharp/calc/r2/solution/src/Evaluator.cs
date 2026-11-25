namespace Calc;

/// <summary>
/// Recursive-descent evaluator for signed 64-bit integer expressions:
/// <code>
/// expr    := term    (('+' | '-') term)*
/// term    := unary   (('*' | '/' | '%') unary)*
/// unary   := '-' unary | primary
/// primary := NUMBER | '(' expr ')'
/// </code>
/// Any syntax error, division by zero or overflow makes evaluation fail.
/// </summary>
internal ref struct Evaluator
{
    private readonly ReadOnlySpan<byte> _text;
    private int _pos;

    private Evaluator(ReadOnlySpan<byte> text)
    {
        _text = text;
        _pos = 0;
    }

    public static bool TryEvaluate(ReadOnlySpan<byte> text, out long value)
    {
        var evaluator = new Evaluator(text);
        if (!evaluator.TryExpr(out value))
        {
            return false;
        }

        evaluator.SkipWhitespace();
        return evaluator._pos == text.Length;
    }

    private bool TryExpr(out long value)
    {
        if (!TryTerm(out value))
        {
            return false;
        }

        while (true)
        {
            byte op = Peek();
            if (op is not ((byte)'+' or (byte)'-'))
            {
                return true;
            }

            _pos++;
            if (!TryTerm(out long rhs) || !Arithmetic.TryApply(op, value, rhs, out value))
            {
                return false;
            }
        }
    }

    private bool TryTerm(out long value)
    {
        if (!TryUnary(out value))
        {
            return false;
        }

        while (true)
        {
            byte op = Peek();
            if (op is not ((byte)'*' or (byte)'/' or (byte)'%'))
            {
                return true;
            }

            _pos++;
            if (!TryUnary(out long rhs) || !Arithmetic.TryApply(op, value, rhs, out value))
            {
                return false;
            }
        }
    }

    private bool TryUnary(out long value)
    {
        if (Peek() == (byte)'-')
        {
            _pos++;
            if (!TryUnary(out long operand) || operand == long.MinValue)
            {
                value = 0;
                return false;
            }

            value = -operand;
            return true;
        }

        return TryPrimary(out value);
    }

    private bool TryPrimary(out long value)
    {
        value = 0;
        byte next = Peek();

        if (next == (byte)'(')
        {
            _pos++;
            if (!TryExpr(out value) || Peek() != (byte)')')
            {
                return false;
            }

            _pos++;
            return true;
        }

        return char.IsAsciiDigit((char)next) && TryNumber(out value);
    }

    private bool TryNumber(out long value)
    {
        value = 0;
        while (_pos < _text.Length && char.IsAsciiDigit((char)_text[_pos]))
        {
            int digit = _text[_pos++] - '0';
            if (value > (long.MaxValue - digit) / 10)
            {
                return false;
            }

            value = (value * 10) + digit;
        }

        return true;
    }

    /// <summary>Skips whitespace and returns the next byte without consuming it, or 0 at end of input.</summary>
    private byte Peek()
    {
        SkipWhitespace();
        return _pos < _text.Length ? _text[_pos] : (byte)0;
    }

    private void SkipWhitespace()
    {
        while (_pos < _text.Length && _text[_pos] is (byte)' ' or (byte)'\t')
        {
            _pos++;
        }
    }
}
