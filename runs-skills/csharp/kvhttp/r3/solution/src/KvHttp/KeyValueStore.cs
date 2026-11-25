namespace KvHttp;

/// <summary>Thread-safe in-memory key-value store.</summary>
public sealed class KeyValueStore
{
    private readonly Lock _gate = new();
    private readonly Dictionary<string, byte[]> _items = new(StringComparer.Ordinal);

    /// <summary>Stores <paramref name="value"/>; returns <c>true</c> if the key was new.</summary>
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
            return _items.TryGetValue(key, out value!);
        }
    }

    public bool Remove(string key)
    {
        lock (_gate)
        {
            return _items.Remove(key);
        }
    }

    /// <summary>All keys, sorted ascending by ordinal comparison.</summary>
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
