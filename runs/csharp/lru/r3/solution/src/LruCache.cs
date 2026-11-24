namespace Lru;

/// <summary>
/// A fixed-capacity least-recently-used cache with O(1) expected-time operations.
/// Entries live in parallel arrays linked into a doubly linked recency list
/// (head = most recent, tail = least recent); freed slots are recycled.
/// </summary>
public sealed class LruCache
{
    private const int None = -1;

    private readonly int _capacity;
    private readonly Dictionary<string, int> _index;
    private readonly Dictionary<string, int>.AlternateLookup<ReadOnlySpan<char>> _spanIndex;

    private string[] _keys;
    private string[] _values;
    private int[] _prev;
    private int[] _next;

    private int _head = None;
    private int _tail = None;
    private int _freeList = None;
    private int _used;

    public LruCache(int capacity)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(capacity, 1);
        _capacity = capacity;

        int initial = Math.Min(capacity, 1024);
        _index = new Dictionary<string, int>(initial, StringComparer.Ordinal);
        _spanIndex = _index.GetAlternateLookup<ReadOnlySpan<char>>();
        _keys = new string[initial];
        _values = new string[initial];
        _prev = new int[initial];
        _next = new int[initial];
    }

    public int Count => _index.Count;

    public void Set(ReadOnlySpan<char> key, ReadOnlySpan<char> value)
    {
        if (_spanIndex.TryGetValue(key, out int slot))
        {
            _values[slot] = value.ToString();
            MoveToFront(slot);
            return;
        }

        string keyString = key.ToString();
        slot = AllocateSlot();
        _keys[slot] = keyString;
        _values[slot] = value.ToString();
        _index.Add(keyString, slot);
        LinkAtFront(slot);

        if (_index.Count > _capacity)
        {
            RemoveSlot(_tail);
        }
    }

    public bool TryGet(ReadOnlySpan<char> key, out string? value)
    {
        if (_spanIndex.TryGetValue(key, out int slot))
        {
            MoveToFront(slot);
            value = _values[slot];
            return true;
        }

        value = null;
        return false;
    }

    public bool Remove(ReadOnlySpan<char> key)
    {
        if (!_spanIndex.TryGetValue(key, out int slot))
        {
            return false;
        }

        RemoveSlot(slot);
        return true;
    }

    private void RemoveSlot(int slot)
    {
        _index.Remove(_keys[slot]);
        Unlink(slot);
        _keys[slot] = null!;
        _values[slot] = null!;
        _next[slot] = _freeList;
        _freeList = slot;
    }

    private int AllocateSlot()
    {
        if (_freeList != None)
        {
            int slot = _freeList;
            _freeList = _next[slot];
            return slot;
        }

        if (_used == _keys.Length)
        {
            // Capacity + 1 slots are needed transiently before an eviction.
            int newSize = (int)Math.Min((long)_keys.Length * 2, (long)_capacity + 1);
            Array.Resize(ref _keys, newSize);
            Array.Resize(ref _values, newSize);
            Array.Resize(ref _prev, newSize);
            Array.Resize(ref _next, newSize);
        }

        return _used++;
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
