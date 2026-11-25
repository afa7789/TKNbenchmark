namespace Lru;

/// <summary>
/// A fixed-capacity least-recently-used cache with O(1) expected-time operations.
/// Entries live in a pooled array and are threaded onto an intrusive doubly linked
/// list ordered from most to least recently used.
/// </summary>
public sealed class LruCache<TKey, TValue>
    where TKey : notnull
{
    private const int None = -1;

    private struct Entry
    {
        public TKey Key;
        public TValue Value;
        public int Prev;
        public int Next;
    }

    private readonly Dictionary<TKey, int> _index;
    private Entry[] _entries;
    private int _allocated;
    private int _freeHead = None;
    private int _head = None; // most recently used
    private int _tail = None; // least recently used

    public LruCache(int capacity, IEqualityComparer<TKey>? comparer = null)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(capacity, 1);
        Capacity = capacity;
        int initial = Math.Min(capacity, 1024);
        _index = new Dictionary<TKey, int>(initial, comparer);
        _entries = new Entry[initial];
    }

    public int Capacity { get; }

    public int Count => _index.Count;

    public void Set(TKey key, TValue value)
    {
        if (_index.TryGetValue(key, out int slot))
        {
            _entries[slot].Value = value;
            MoveToFront(slot);
            return;
        }

        if (_index.Count == Capacity)
        {
            Remove(_tail);
        }

        slot = AllocateSlot();
        ref Entry entry = ref _entries[slot];
        entry.Key = key;
        entry.Value = value;
        LinkAtFront(slot);
        _index.Add(key, slot);
    }

    public bool TryGet(TKey key, out TValue value) =>
        TryGetSlot(_index.TryGetValue(key, out int slot), slot, out value);

    public bool Remove(TKey key)
    {
        if (!_index.TryGetValue(key, out int slot))
        {
            return false;
        }

        Remove(slot);
        return true;
    }

    /// <summary>Looks up a key through an alternate representation without materialising it.</summary>
    public bool TryGet<TAlternate>(TAlternate key, out TValue value)
        where TAlternate : notnull, allows ref struct
    {
        var lookup = _index.GetAlternateLookup<TAlternate>();
        return TryGetSlot(lookup.TryGetValue(key, out int slot), slot, out value);
    }

    /// <summary>Removes a key given in an alternate representation.</summary>
    public bool Remove<TAlternate>(TAlternate key)
        where TAlternate : notnull, allows ref struct
    {
        var lookup = _index.GetAlternateLookup<TAlternate>();
        if (!lookup.TryGetValue(key, out int slot))
        {
            return false;
        }

        Remove(slot);
        return true;
    }

    private bool TryGetSlot(bool found, int slot, out TValue value)
    {
        if (!found)
        {
            value = default!;
            return false;
        }

        MoveToFront(slot);
        value = _entries[slot].Value;
        return true;
    }

    private void Remove(int slot)
    {
        ref Entry entry = ref _entries[slot];
        _index.Remove(entry.Key);
        Unlink(slot);
        entry.Key = default!;
        entry.Value = default!;
        entry.Next = _freeHead;
        _freeHead = slot;
    }

    private int AllocateSlot()
    {
        if (_freeHead != None)
        {
            int slot = _freeHead;
            _freeHead = _entries[slot].Next;
            return slot;
        }

        if (_allocated == _entries.Length)
        {
            int newSize = (int)Math.Min((long)_entries.Length * 2, Capacity);
            Array.Resize(ref _entries, newSize);
        }

        return _allocated++;
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
        ref Entry entry = ref _entries[slot];
        entry.Prev = None;
        entry.Next = _head;
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
        ref Entry entry = ref _entries[slot];
        if (entry.Prev != None)
        {
            _entries[entry.Prev].Next = entry.Next;
        }
        else
        {
            _head = entry.Next;
        }

        if (entry.Next != None)
        {
            _entries[entry.Next].Prev = entry.Prev;
        }
        else
        {
            _tail = entry.Prev;
        }
    }
}
