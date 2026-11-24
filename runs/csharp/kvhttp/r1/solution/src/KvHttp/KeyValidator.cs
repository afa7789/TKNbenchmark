namespace KvHttp;

public static class KeyValidator
{
    public const int MaxLength = 64;

    /// <summary>A key matches <c>[A-Za-z0-9_-]{1,64}</c>.</summary>
    public static bool IsValid(ReadOnlySpan<char> key)
    {
        if (key.Length is 0 or > MaxLength)
        {
            return false;
        }

        foreach (var c in key)
        {
            if (!(char.IsAsciiLetterOrDigit(c) || c is '_' or '-'))
            {
                return false;
            }
        }

        return true;
    }
}
