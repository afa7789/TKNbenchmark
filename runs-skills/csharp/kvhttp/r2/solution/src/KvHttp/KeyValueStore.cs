namespace KvHttp;

/// <summary>Thread-safe in-memory map from keys to opaque byte values.</summary>
public sealed class KeyValueStore
{
    private readonly Dictionary<string, byte[]> _entries = new(StringComparer.Ordinal);
    private readonly Lock _gate = new();

    /// <summary>Stores <paramref name="value"/> under <paramref name="key"/>.</summary>
    /// <returns><see langword="true"/> if the key was newly created; <see langword="false"/> if a value was replaced.</returns>
    public bool Put(string key, byte[] value)
    {
        ArgumentNullException.ThrowIfNull(key);
        ArgumentNullException.ThrowIfNull(value);
        lock (_gate)
        {
            bool created = !_entries.ContainsKey(key);
            _entries[key] = value;
            return created;
        }
    }

    public bool TryGet(string key, out byte[] value)
    {
        lock (_gate)
        {
            return _entries.TryGetValue(key, out value!);
        }
    }

    public bool Remove(string key)
    {
        lock (_gate)
        {
            return _entries.Remove(key);
        }
    }

    /// <summary>Returns a snapshot of all keys in ordinal ascending order.</summary>
    public string[] SortedKeys()
    {
        string[] keys;
        lock (_gate)
        {
            keys = [.. _entries.Keys];
        }
        Array.Sort(keys, StringComparer.Ordinal);
        return keys;
    }
}
