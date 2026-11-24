namespace Calc;

/// <summary>Overflow-aware 64-bit arithmetic that reports failure instead of throwing.</summary>
internal static class Checked
{
    public static bool TryAdd(long a, long b, out long result)
    {
        result = unchecked(a + b);
        // Overflow iff both operands share a sign that differs from the result's.
        return ((a ^ result) & (b ^ result)) >= 0;
    }

    public static bool TrySubtract(long a, long b, out long result)
    {
        result = unchecked(a - b);
        // Overflow iff operands differ in sign and the result's sign differs from a's.
        return ((a ^ b) & (a ^ result)) >= 0;
    }

    public static bool TryMultiply(long a, long b, out long result)
    {
        long high = Math.BigMul(a, b, out long low);
        result = low;
        return high == (low >> 63);
    }

    public static bool TryDivide(long a, long b, out long result)
    {
        if (b == 0 || (a == long.MinValue && b == -1))
        {
            result = 0;
            return false;
        }

        result = a / b;
        return true;
    }

    public static bool TryRemainder(long a, long b, out long result)
    {
        if (b == 0)
        {
            result = 0;
            return false;
        }

        // long.MinValue % -1 would trap on some platforms; mathematically it is 0.
        result = b == -1 ? 0 : a % b;
        return true;
    }
}
