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
/// </code>
/// </remarks>
public ref struct Evaluator
{
    private readonly ReadOnlySpan<byte> _text;
    private int _pos;

    private Evaluator(ReadOnlySpan<byte> text)
    {
        _text = text;
        _pos = 0;
    }

    /// <summary>
    /// Evaluates one expression. Returns <c>false</c> on a syntax error,
    /// division by zero, or 64-bit overflow.
    /// </summary>
    public static bool TryEvaluate(ReadOnlySpan<byte> text, out long value)
    {
        var evaluator = new Evaluator(text);
        try
        {
            value = evaluator.ParseExpr();
            evaluator.SkipWhitespace();
            if (evaluator._pos != text.Length)
            {
                throw new EvaluationException();
            }
            return true;
        }
        catch (Exception ex) when (ex is EvaluationException or OverflowException or DivideByZeroException)
        {
            value = 0;
            return false;
        }
    }

    private long ParseExpr()
    {
        long left = ParseTerm();
        while (true)
        {
            switch (Peek())
            {
                case (byte)'+':
                    _pos++;
                    left = checked(left + ParseTerm());
                    break;
                case (byte)'-':
                    _pos++;
                    left = checked(left - ParseTerm());
                    break;
                default:
                    return left;
            }
        }
    }

    private long ParseTerm()
    {
        long left = ParseUnary();
        while (true)
        {
            switch (Peek())
            {
                case (byte)'*':
                    _pos++;
                    left = checked(left * ParseUnary());
                    break;
                case (byte)'/':
                    _pos++;
                    left = Divide(left, ParseUnary());
                    break;
                case (byte)'%':
                    _pos++;
                    left = Remainder(left, ParseUnary());
                    break;
                default:
                    return left;
            }
        }
    }

    private long ParseUnary()
    {
        if (Peek() == (byte)'-')
        {
            _pos++;
            return checked(-ParseUnary());
        }
        return ParsePrimary();
    }

    private long ParsePrimary()
    {
        byte c = Peek();
        if (c == (byte)'(')
        {
            _pos++;
            long inner = ParseExpr();
            if (Peek() != (byte)')')
            {
                throw new EvaluationException();
            }
            _pos++;
            return inner;
        }
        if (IsDigit(c))
        {
            return ParseNumber();
        }
        throw new EvaluationException();
    }

    private long ParseNumber()
    {
        long result = 0;
        while (_pos < _text.Length && IsDigit(_text[_pos]))
        {
            result = checked((result * 10) + (_text[_pos] - '0'));
            _pos++;
        }
        return result;
    }

    private static long Divide(long dividend, long divisor)
    {
        if (divisor == 0)
        {
            throw new DivideByZeroException();
        }
        return checked(dividend / divisor);
    }

    private static long Remainder(long dividend, long divisor)
    {
        if (divisor == 0)
        {
            throw new DivideByZeroException();
        }
        // long.MinValue % -1 would trap on some platforms; the true remainder is 0.
        return divisor == -1 ? 0 : dividend % divisor;
    }

    /// <summary>Skips whitespace and returns the next byte, or 0 at end of input.</summary>
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

    private static bool IsDigit(byte c) => c is >= (byte)'0' and <= (byte)'9';

    private sealed class EvaluationException : Exception;
}
