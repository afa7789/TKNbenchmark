namespace Calc;

/// <summary>
/// Reads '\n'-terminated lines from a byte stream without decoding them.
/// The final line is returned even if it lacks a terminator.
/// </summary>
public sealed class LineReader(Stream stream, int initialCapacity = 1 << 16)
{
    private readonly Stream _stream = stream;
    private byte[] _buffer = new byte[initialCapacity];
    private int _start;
    private int _end;
    private bool _eof;

    /// <summary>
    /// Returns the next line (without its '\n'). The span is valid only until the next call.
    /// </summary>
    public bool TryReadLine(out ReadOnlySpan<byte> line)
    {
        int scanFrom = _start;
        while (true)
        {
            int newline = _buffer.AsSpan(scanFrom, _end - scanFrom).IndexOf((byte)'\n');
            if (newline >= 0)
            {
                int lineEnd = scanFrom + newline;
                line = _buffer.AsSpan(_start, lineEnd - _start);
                _start = lineEnd + 1;
                return true;
            }

            if (_eof)
            {
                if (_start < _end)
                {
                    line = _buffer.AsSpan(_start, _end - _start);
                    _start = _end;
                    return true;
                }

                line = default;
                return false;
            }

            scanFrom = _end - _start;
            Fill();
        }
    }

    private void Fill()
    {
        // Compact pending data to the front, growing if the buffer is full of one line.
        int pending = _end - _start;
        if (pending == _buffer.Length)
        {
            Array.Resize(ref _buffer, _buffer.Length * 2);
        }
        else if (_start > 0)
        {
            Buffer.BlockCopy(_buffer, _start, _buffer, 0, pending);
        }

        _start = 0;
        _end = pending;

        int read = _stream.Read(_buffer, _end, _buffer.Length - _end);
        if (read == 0)
        {
            _eof = true;
        }
        else
        {
            _end += read;
        }
    }
}
