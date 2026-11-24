namespace Lru;

/// <summary>
/// A fixed-capacity least-recently-used cache. All operations run in O(1) expected time.
/// </summary>
/// <remarks>
/// Entries live in parallel arrays forming an intrusive doubly linked list ordered from
/// most recently used (head) to least recently used (tail). Freed slots are recycled through
/// a free list, so steady-state operation performs no per-entry allocation beyond the keys
/// and values themselves.
/// </remarks>
public sealed class LruCache<TKey, TValue> where TKey : notnull
{
    private const int None = -1;

    private readonly int _capacity;
    private readonly Dictionary<TKey, int> _index;
    private TKey[] _keys;
    private TValue[] _values;
    private int[] _prev;
    private int[] _next;
    private int _head = None;
    private int _tail = None;
    private int _freeHead = None;
    private int _allocated;

    public LruCache(int capacity, IEqualityComparer<TKey>? comparer = null)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(capacity, 1);
        _capacity = capacity;

        int initial = Math.Min(capacity, 1024);
        _index = new Dictionary<TKey, int>(initial, comparer);
        _keys = new TKey[initial];
        _values = new TValue[initial];
        _prev = new int[initial];
        _next = new int[initial];
    }

    public int Count => _index.Count;

    public int Capacity => _capacity;

    /// <summary>Inserts or overwrites a key, making it the most recently used.</summary>
    public void Set(TKey key, TValue value)
    {
        if (_index.TryGetValue(key, out int slot))
        {
            _values[slot] = value;
            MoveToFront(slot);
            return;
        }

        if (_index.Count == _capacity)
        {
            EvictLeastRecentlyUsed();
        }

        slot = AllocateSlot();
        _keys[slot] = key;
        _values[slot] = value;
        LinkAtFront(slot);
        _index.Add(key, slot);
    }

    /// <summary>Looks up a key; a hit makes it the most recently used.</summary>
    public bool TryGet(TKey key, out TValue value)
    {
        if (_index.TryGetValue(key, out int slot))
        {
            MoveToFront(slot);
            value = _values[slot];
            return true;
        }

        value = default!;
        return false;
    }

    /// <summary>Removes a key. Returns <c>true</c> if it was present.</summary>
    public bool Remove(TKey key)
    {
        if (!_index.Remove(key, out int slot))
        {
            return false;
        }

        Unlink(slot);
        ReleaseSlot(slot);
        return true;
    }

    private void EvictLeastRecentlyUsed()
    {
        int victim = _tail;
        _index.Remove(_keys[victim]);
        Unlink(victim);
        ReleaseSlot(victim);
    }

    private int AllocateSlot()
    {
        if (_freeHead != None)
        {
            int slot = _freeHead;
            _freeHead = _next[slot];
            return slot;
        }

        if (_allocated == _keys.Length)
        {
            Grow();
        }

        return _allocated++;
    }

    private void ReleaseSlot(int slot)
    {
        _keys[slot] = default!;
        _values[slot] = default!;
        _next[slot] = _freeHead;
        _freeHead = slot;
    }

    private void Grow()
    {
        int newSize = (int)Math.Min((long)_keys.Length * 2, _capacity);
        Array.Resize(ref _keys, newSize);
        Array.Resize(ref _values, newSize);
        Array.Resize(ref _prev, newSize);
        Array.Resize(ref _next, newSize);
    }

    private void MoveToFront(int slot)
    {
        if (slot == _head)
        {
            return;
        }

        Unlink(slot);
        LinkAtFront(slot);
    }

    private void LinkAtFront(int slot)
    {
        _prev[slot] = None;
        _next[slot] = _head;
        if (_head != None)
        {
            _prev[_head] = slot;
        }
        else
        {
            _tail = slot;
        }

        _head = slot;
    }

    private void Unlink(int slot)
    {
        int prev = _prev[slot];
        int next = _next[slot];

        if (prev != None)
        {
            _next[prev] = next;
        }
        else
        {
            _head = next;
        }

        if (next != None)
        {
            _prev[next] = prev;
        }
        else
        {
            _tail = prev;
        }
    }
}
