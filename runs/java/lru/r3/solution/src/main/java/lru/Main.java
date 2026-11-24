package lru;

import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/** Reads LRU cache commands from standard input and writes results to standard output. */
public final class Main {

    private static final byte[] NULL = "NULL".getBytes(StandardCharsets.US_ASCII);

    private Main() {
    }

    public static void main(String[] args) throws IOException {
        byte[] input = System.in.readAllBytes();
        try (OutputStream out = new BufferedOutputStream(new FileOutputStream(FileDescriptor.out), 1 << 16)) {
            run(input, out);
        }
    }

    static void run(byte[] input, OutputStream out) throws IOException {
        LineReader lines = new LineReader(input);
        String first = lines.next();
        while (first != null && first.isBlank()) {
            first = lines.next();
        }
        if (first == null) {
            return;
        }
        LruCache<String, String> cache = new LruCache<>(Integer.parseInt(first.strip()));

        String line;
        while ((line = lines.next()) != null) {
            execute(cache, line, out);
        }
    }

    private static void execute(LruCache<String, String> cache, String line, OutputStream out)
            throws IOException {
        int firstSpace = line.indexOf(' ');
        String command = firstSpace < 0 ? line : line.substring(0, firstSpace);
        switch (command) {
            case "SET" -> {
                int secondSpace = line.indexOf(' ', firstSpace + 1);
                if (firstSpace < 0 || secondSpace < 0) {
                    return;
                }
                cache.set(line.substring(firstSpace + 1, secondSpace), line.substring(secondSpace + 1));
            }
            case "GET" -> {
                if (firstSpace < 0) {
                    return;
                }
                String value = cache.get(line.substring(firstSpace + 1));
                writeLine(out, value == null ? NULL : value.getBytes(StandardCharsets.ISO_8859_1));
            }
            case "DEL" -> {
                if (firstSpace < 0) {
                    return;
                }
                out.write(cache.delete(line.substring(firstSpace + 1)) ? '1' : '0');
                out.write('\n');
            }
            case "SIZE" -> writeLine(out, Integer.toString(cache.size()).getBytes(StandardCharsets.US_ASCII));
            default -> {
                // Blank or unrecognised lines produce no output.
            }
        }
    }

    private static void writeLine(OutputStream out, byte[] bytes) throws IOException {
        out.write(bytes);
        out.write('\n');
    }

    /** Splits a byte buffer into lines, tolerating a trailing {@code \r} and a missing final newline. */
    private static final class LineReader {
        private final byte[] data;
        private int pos;

        LineReader(byte[] data) {
            this.data = data;
        }

        String next() {
            if (pos >= data.length) {
                return null;
            }
            int start = pos;
            int end = start;
            while (end < data.length && data[end] != '\n') {
                end++;
            }
            pos = end + 1;
            if (end > start && data[end - 1] == '\r') {
                end--;
            }
            return new String(data, start, end - start, StandardCharsets.ISO_8859_1);
        }
    }
}
