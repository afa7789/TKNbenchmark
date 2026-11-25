namespace KvHttp;

/// <summary>Thread-safe in-memory store mapping keys to opaque byte values.</summary>
public sealed class KeyValueStore
{
    private readonly Dictionary<string, byte[]> _items = new(StringComparer.Ordinal);
    private readonly Lock _gate = new();

    /// <summary>Stores <paramref name="value"/> under <paramref name="key"/>.</summary>
    /// <returns><see langword="true"/> if the key was new; <see langword="false"/> if a value was replaced.</returns>
    public bool Put(string key, byte[] value)
    {
        ArgumentNullException.ThrowIfNull(key);
        ArgumentNullException.ThrowIfNull(value);
        lock (_gate)
        {
            bool isNew = !_items.ContainsKey(key);
            _items[key] = value;
            return isNew;
        }
    }

    public bool TryGet(string key, out byte[] value)
    {
        lock (_gate)
        {
            if (_items.TryGetValue(key, out byte[]? found))
            {
                value = found;
                return true;
            }
        }

        value = [];
        return false;
    }

    public bool Remove(string key)
    {
        lock (_gate)
        {
            return _items.Remove(key);
        }
    }

    /// <summary>Returns a snapshot of all keys in ascending ordinal order.</summary>
    public string[] SortedKeys()
    {
        string[] keys;
        lock (_gate)
        {
            keys = [.. _items.Keys];
        }

        Array.Sort(keys, StringComparer.Ordinal);
        return keys;
    }
}
