// Package input provides helpers for reading program input shared by the subcommands.
package input

import "core:os"

// INITIAL_BUFFER_SIZE is the starting size of the buffer used by read_all; it doubles as needed.
INITIAL_BUFFER_SIZE :: 1 << 20

// read_all reads `f` until end of file. Unlike os.read_entire_file it does not trust the
// reported file size, which for a pipe on some platforms is only the currently buffered amount.
// The returned slice is allocated with `allocator` and owned by the caller.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	buf := make([dynamic]byte, INITIAL_BUFFER_SIZE, allocator) or_return
	total := 0
	for {
		if total == len(buf) {
			if rerr := non_zero_resize(&buf, 2 * len(buf)); rerr != nil {
				delete(buf)
				return nil, rerr
			}
		}
		n, rerr := os.read(f, buf[total:])
		total += n
		if rerr == .EOF || rerr == .Broken_Pipe || (rerr == nil && n == 0) {
			break
		}
		if rerr != nil {
			delete(buf)
			return nil, rerr
		}
	}
	return buf[:total], nil
}
