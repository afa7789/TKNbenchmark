package lru;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.FileDescriptor;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;

/** Reads LRU cache commands from standard input and writes results to standard output. */
public final class Main {

    private static final int BUFFER_SIZE = 1 << 16;

    private Main() {
    }

    public static void main(String[] args) throws IOException {
        var in = new BufferedReader(
                new InputStreamReader(new FileInputStream(FileDescriptor.in), StandardCharsets.ISO_8859_1),
                BUFFER_SIZE);
        var out = new BufferedWriter(
                new OutputStreamWriter(new FileOutputStream(FileDescriptor.out), StandardCharsets.ISO_8859_1),
                BUFFER_SIZE);
        try (in; out) {
            run(in, out);
        }
    }

    static void run(BufferedReader in, Writer out) throws IOException {
        String header = in.readLine();
        if (header == null) {
            return;
        }
        var cache = new LruCache<String, String>(Integer.parseInt(header.strip()));
        String line;
        while ((line = in.readLine()) != null) {
            execute(cache, stripCarriageReturn(line), out);
        }
    }

    private static void execute(LruCache<String, String> cache, String line, Writer out) throws IOException {
        int firstSpace = line.indexOf(' ');
        String command = firstSpace < 0 ? line : line.substring(0, firstSpace);
        switch (command) {
            case "SET" -> {
                int secondSpace = line.indexOf(' ', firstSpace + 1);
                if (secondSpace < 0) {
                    return;
                }
                cache.put(line.substring(firstSpace + 1, secondSpace), line.substring(secondSpace + 1));
            }
            case "GET" -> {
                if (firstSpace < 0) {
                    return;
                }
                String value = cache.get(line.substring(firstSpace + 1));
                writeLine(out, value == null ? "NULL" : value);
            }
            case "DEL" -> {
                if (firstSpace < 0) {
                    return;
                }
                writeLine(out, cache.remove(line.substring(firstSpace + 1)) ? "1" : "0");
            }
            case "SIZE" -> writeLine(out, Integer.toString(cache.size()));
            default -> {
                // Blank or unrecognised lines are ignored.
            }
        }
    }

    private static String stripCarriageReturn(String line) {
        int end = line.length();
        return end > 0 && line.charAt(end - 1) == '\r' ? line.substring(0, end - 1) : line;
    }

    private static void writeLine(Writer out, String text) throws IOException {
        out.write(text);
        out.write('\n');
    }
}
