namespace Lru;

/// <summary>
/// A fixed-capacity least-recently-used cache. All operations run in O(1) expected time.
/// Entries live in parallel arrays linked into a doubly linked recency list, which avoids
/// a heap allocation per node.
/// </summary>
public sealed class LruCache<TKey, TValue> where TKey : notnull
{
    private const int None = -1;

    private readonly int _capacity;
    private readonly Dictionary<TKey, int> _index;
    private TKey[] _keys;
    private TValue[] _values;
    private int[] _prev;
    private int[] _next;
    private int _head = None; // most recently used
    private int _tail = None; // least recently used
    private int _freeList = None;
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
            int victim = _tail;
            _index.Remove(_keys[victim]);
            Unlink(victim);
            Release(victim);
        }

        slot = Allocate();
        _keys[slot] = key;
        _values[slot] = value;
        _index.Add(key, slot);
        LinkFront(slot);
    }

    public bool Remove(TKey key)
    {
        if (!_index.Remove(key, out int slot))
        {
            return false;
        }

        Unlink(slot);
        Release(slot);
        return true;
    }

    private int Allocate()
    {
        if (_freeList != None)
        {
            int slot = _freeList;
            _freeList = _next[slot];
            return slot;
        }

        if (_allocated == _keys.Length)
        {
            int size = (int)Math.Min((long)_keys.Length * 2, _capacity);
            Array.Resize(ref _keys, size);
            Array.Resize(ref _values, size);
            Array.Resize(ref _prev, size);
            Array.Resize(ref _next, size);
        }

        return _allocated++;
    }

    private void Release(int slot)
    {
        _keys[slot] = default!;
        _values[slot] = default!;
        _next[slot] = _freeList;
        _freeList = slot;
    }

    private void MoveToFront(int slot)
    {
        if (slot == _head)
        {
            return;
        }

        Unlink(slot);
        LinkFront(slot);
    }

    private void LinkFront(int slot)
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
        int p = _prev[slot];
        int n = _next[slot];
        if (p != None)
        {
            _next[p] = n;
        }
        else
        {
            _head = n;
        }

        if (n != None)
        {
            _prev[n] = p;
        }
        else
        {
            _tail = p;
        }
    }
}
