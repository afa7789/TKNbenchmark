using System.Buffers;

namespace KvHttp;

public static class KeyValidator
{
    public const int MaxLength = 64;

    private static readonly SearchValues<char> s_allowed =
        SearchValues.Create("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-");

    /// <summary>Returns whether <paramref name="key"/> matches <c>[A-Za-z0-9_-]{1,64}</c>.</summary>
    public static bool IsValid(ReadOnlySpan<char> key) =>
        key.Length is > 0 and <= MaxLength && !key.ContainsAnyExcept(s_allowed);
}
