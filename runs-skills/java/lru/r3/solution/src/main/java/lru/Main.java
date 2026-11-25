package lru;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;

/// Reads a capacity and a stream of cache commands from standard input and writes the
/// results to standard output. See SPEC.md for the command language.
public final class Main {

    private static final String MISS = "NULL";

    private Main() {}

    public static void main(String[] args) throws IOException {
        var in = new BufferedReader(
                new InputStreamReader(System.in, StandardCharsets.ISO_8859_1), 1 << 16);
        var out = new BufferedWriter(
                new OutputStreamWriter(System.out, StandardCharsets.ISO_8859_1), 1 << 16);
        run(in, out);
        out.flush();
    }

    static void run(BufferedReader in, Writer out) throws IOException {
        String header = nextNonBlankLine(in);
        if (header == null) {
            return;
        }
        var cache = new LruCache<String, String>(Integer.parseInt(header.strip()));

        String line;
        while ((line = in.readLine()) != null) {
            line = stripCarriageReturn(line);
            if (line.isEmpty()) {
                continue;
            }
            execute(cache, line, out);
        }
    }

    private static void execute(LruCache<String, String> cache, String line, Writer out)
            throws IOException {
        int firstSpace = line.indexOf(' ');
        String command = firstSpace < 0 ? line : line.substring(0, firstSpace);
        switch (command) {
            case "SET" -> {
                int secondSpace = line.indexOf(' ', firstSpace + 1);
                if (secondSpace < 0) {
                    throw new IllegalArgumentException("malformed SET: " + line);
                }
                cache.put(line.substring(firstSpace + 1, secondSpace), line.substring(secondSpace + 1));
            }
            case "GET" -> {
                String value = cache.get(argument(line, firstSpace));
                writeLine(out, value == null ? MISS : value);
            }
            case "DEL" -> writeLine(out, cache.remove(argument(line, firstSpace)) ? "1" : "0");
            case "SIZE" -> writeLine(out, Integer.toString(cache.size()));
            default -> throw new IllegalArgumentException("unknown command: " + line);
        }
    }

    private static String argument(String line, int firstSpace) {
        if (firstSpace < 0) {
            throw new IllegalArgumentException("missing key: " + line);
        }
        return line.substring(firstSpace + 1);
    }

    private static void writeLine(Writer out, String s) throws IOException {
        out.write(s);
        out.write('\n');
    }

    private static String nextNonBlankLine(BufferedReader in) throws IOException {
        String line;
        while ((line = in.readLine()) != null) {
            if (!line.isBlank()) {
                return line;
            }
        }
        return null;
    }

    private static String stripCarriageReturn(String line) {
        return line.endsWith("\r") ? line.substring(0, line.length() - 1) : line;
    }
}
