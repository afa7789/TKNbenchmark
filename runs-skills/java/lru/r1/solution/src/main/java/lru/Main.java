package lru;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;

/// Reads a capacity and a stream of cache commands from standard input and writes the results
/// of `GET`, `DEL` and `SIZE` to standard output, one per line.
public final class Main {

    private static final int BUFFER_SIZE = 1 << 16;

    private Main() {}

    public static void main(String[] args) throws IOException {
        var in = new BufferedReader(
                new InputStreamReader(System.in, StandardCharsets.US_ASCII), BUFFER_SIZE);
        var out = new PrintWriter(new BufferedWriter(
                new OutputStreamWriter(System.out, StandardCharsets.US_ASCII), BUFFER_SIZE));
        try {
            run(in, out);
        } finally {
            out.flush();
        }
        if (out.checkError()) {
            throw new UncheckedIOException(new IOException("error writing standard output"));
        }
    }

    static void run(BufferedReader in, PrintWriter out) throws IOException {
        String header = in.readLine();
        if (header == null || header.isBlank()) {
            return;
        }
        var cache = new LruCache<String, String>(Integer.parseInt(header.strip()));
        for (String line; (line = in.readLine()) != null; ) {
            execute(cache, stripCarriageReturn(line), out);
        }
    }

    private static void execute(LruCache<String, String> cache, String line, PrintWriter out) {
        int firstSpace = line.indexOf(' ');
        String command = firstSpace < 0 ? line : line.substring(0, firstSpace);
        switch (command) {
            case "SET" -> {
                int secondSpace = line.indexOf(' ', firstSpace + 1);
                if (firstSpace < 0 || secondSpace < 0) {
                    throw new IllegalArgumentException("malformed SET: " + line);
                }
                cache.put(line.substring(firstSpace + 1, secondSpace),
                        line.substring(secondSpace + 1));
            }
            case "GET" -> {
                String value = cache.get(argument(line, firstSpace));
                out.println(value == null ? "NULL" : value);
            }
            case "DEL" -> out.println(cache.remove(argument(line, firstSpace)) ? '1' : '0');
            case "SIZE" -> out.println(cache.size());
            case "" -> { } // tolerate blank lines
            default -> throw new IllegalArgumentException("unknown command: " + line);
        }
    }

    private static String argument(String line, int firstSpace) {
        if (firstSpace < 0) {
            throw new IllegalArgumentException("missing key: " + line);
        }
        return line.substring(firstSpace + 1);
    }

    private static String stripCarriageReturn(String line) {
        return line.endsWith("\r") ? line.substring(0, line.length() - 1) : line;
    }
}
