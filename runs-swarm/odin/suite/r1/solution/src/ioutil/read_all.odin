// Helpers shared by the subcommands for reading their input.
package ioutil

import "core:os"

@(private = "file")
READ_CHUNK :: 64 * 1024

// Reads `f` to end of file.
//
// Unlike `os.read_entire_file`, this does not trust the size reported by the
// file: for a pipe that is only what is currently buffered in it, so a
// size-driven read would silently truncate the input.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	buf := make([dynamic]byte, 0, READ_CHUNK, allocator) or_return
	defer if err != nil {
		delete(buf)
		data = nil
	}

	for {
		if cap(buf) - len(buf) < READ_CHUNK {
			reserve(&buf, 2 * cap(buf)) or_return
		}
		start := len(buf)
		resize(&buf, cap(buf)) or_return
		n, read_err := os.read(f, buf[start:])
		resize(&buf, start + n) or_return

		switch read_err {
		case nil:
			if n == 0 {
				return buf[:], nil
			}
		case .EOF, .Broken_Pipe:
			return buf[:], nil
		case:
			return nil, read_err
		}
	}
}
