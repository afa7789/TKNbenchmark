namespace Calc;

/// <summary>Overflow- and zero-checked 64-bit binary operations.</summary>
internal static class Arithmetic
{
    public static bool TryApply(byte op, long lhs, long rhs, out long result)
    {
        result = 0;
        try
        {
            switch (op)
            {
                case (byte)'+':
                    result = checked(lhs + rhs);
                    return true;
                case (byte)'-':
                    result = checked(lhs - rhs);
                    return true;
                case (byte)'*':
                    result = checked(lhs * rhs);
                    return true;
                case (byte)'/':
                    if (rhs == 0 || (lhs == long.MinValue && rhs == -1))
                    {
                        return false;
                    }

                    result = lhs / rhs;
                    return true;
                case (byte)'%':
                    if (rhs == 0)
                    {
                        return false;
                    }

                    // long.MinValue % -1 throws in .NET, but mathematically the remainder is 0.
                    result = rhs == -1 ? 0 : lhs % rhs;
                    return true;
                default:
                    throw new ArgumentOutOfRangeException(nameof(op), op, "Unknown operator.");
            }
        }
        catch (OverflowException)
        {
            return false;
        }
    }
}
