namespace Lru;

/// <summary>
/// A fixed-capacity least-recently-used cache with O(1) expected-time operations.
/// Entries live in a pre-sized array forming an intrusive doubly linked list (most recent at the head),
/// indexed by a dictionary from key to slot.
/// </summary>
public sealed class LruCache
{
    private const int None = -1;

    private struct Entry
    {
        public string Key;
        public string Value;
        public int Prev;
        public int Next;
    }

    private readonly int _capacity;
    private readonly Dictionary<string, int> _index;
    private readonly Dictionary<string, int>.AlternateLookup<ReadOnlySpan<char>> _lookup;
    private readonly Entry[] _entries;
    private int _head = None;
    private int _tail = None;
    private int _freeHead = None;
    private int _used;

    public LruCache(int capacity)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(capacity, 1);
        _capacity = capacity;
        _index = new Dictionary<string, int>(capacity + 1, StringComparer.Ordinal);
        _lookup = _index.GetAlternateLookup<ReadOnlySpan<char>>();
        _entries = new Entry[capacity];
    }

    public int Count => _index.Count;

    public void Set(ReadOnlySpan<char> key, ReadOnlySpan<char> value)
    {
        if (_lookup.TryGetValue(key, out int slot))
        {
            _entries[slot].Value = value.ToString();
            MoveToFront(slot);
            return;
        }

        if (_index.Count == _capacity)
        {
            // Reuse the least recently used slot for the new key.
            slot = _tail;
            _index.Remove(_entries[slot].Key);
            Unlink(slot);
        }
        else
        {
            slot = AllocateSlot();
        }

        string keyString = key.ToString();
        _entries[slot].Key = keyString;
        _entries[slot].Value = value.ToString();
        _index.Add(keyString, slot);
        LinkAtFront(slot);
    }

    public bool TryGet(ReadOnlySpan<char> key, out string value)
    {
        if (_lookup.TryGetValue(key, out int slot))
        {
            MoveToFront(slot);
            value = _entries[slot].Value;
            return true;
        }

        value = string.Empty;
        return false;
    }

    public bool Remove(ReadOnlySpan<char> key)
    {
        if (!_lookup.Remove(key, out _, out int slot))
        {
            return false;
        }

        Unlink(slot);
        _entries[slot] = new Entry { Key = null!, Value = null!, Prev = None, Next = _freeHead };
        _freeHead = slot;
        return true;
    }

    private int AllocateSlot()
    {
        if (_freeHead != None)
        {
            int slot = _freeHead;
            _freeHead = _entries[slot].Next;
            return slot;
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
        ref Entry e = ref _entries[slot];
        e.Prev = None;
        e.Next = _head;
        if (_head != None)
        {
            _entries[_head].Prev = slot;
        }
        else
        {
            _tail = slot;
        }

        _head = slot;
    }

    private void Unlink(int slot)
    {
        ref Entry e = ref _entries[slot];
        if (e.Prev != None)
        {
            _entries[e.Prev].Next = e.Next;
        }
        else
        {
            _head = e.Next;
        }

        if (e.Next != None)
        {
            _entries[e.Next].Prev = e.Prev;
        }
        else
        {
            _tail = e.Prev;
        }

        e.Prev = None;
        e.Next = None;
    }
}
