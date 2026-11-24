namespace KvHttp;

/// <summary>Thread-safe in-memory key-value store.</summary>
public sealed class KvStore
{
    private readonly Dictionary<string, byte[]> _items = new(StringComparer.Ordinal);
    private readonly Lock _lock = new();

    /// <summary>Stores <paramref name="value"/> under <paramref name="key"/>.</summary>
    /// <returns><c>true</c> if the key was newly created, <c>false</c> if an existing value was replaced.</returns>
    public bool Put(string key, byte[] value)
    {
        lock (_lock)
        {
            bool created = !_items.ContainsKey(key);
            _items[key] = value;
            return created;
        }
    }

    public bool TryGet(string key, out byte[] value)
    {
        lock (_lock)
        {
            return _items.TryGetValue(key, out value!);
        }
    }

    public bool Delete(string key)
    {
        lock (_lock)
        {
            return _items.Remove(key);
        }
    }

    public string[] SortedKeys()
    {
        string[] keys;
        lock (_lock)
        {
            keys = [.. _items.Keys];
        }
        Array.Sort(keys, StringComparer.Ordinal);
        return keys;
    }
}
