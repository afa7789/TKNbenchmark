package lru;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;

/// Reads a capacity and a stream of cache commands from standard input and writes
/// the result of each query command to standard output. Malformed commands are
/// reported on standard error and skipped.
public final class Main {

    private static final int BUFFER_SIZE = 1 << 16;

    private Main() {}

    public static void main(String[] args) throws IOException {
        var in = new BufferedReader(
                new InputStreamReader(System.in, StandardCharsets.US_ASCII), BUFFER_SIZE);
        var out = new PrintWriter(new BufferedWriter(
                new OutputStreamWriter(System.out, StandardCharsets.US_ASCII), BUFFER_SIZE), false);
        try {
            run(in, out);
        } finally {
            out.flush();
        }
        if (out.checkError()) {
            throw new UncheckedIOException(new IOException("failed writing to standard output"));
        }
    }

    static void run(BufferedReader in, PrintWriter out) throws IOException {
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

    private static void execute(LruCache<String, String> cache, String line, PrintWriter out) {
        int firstSpace = line.indexOf(' ');
        String command = firstSpace < 0 ? line : line.substring(0, firstSpace);
        switch (command) {
            case "SET" -> {
                int secondSpace = line.indexOf(' ', firstSpace + 1);
                if (secondSpace < 0) {
                    reportMalformed(line);
                    return;
                }
                cache.put(line.substring(firstSpace + 1, secondSpace), line.substring(secondSpace + 1));
            }
            case "GET" -> {
                if (firstSpace < 0) {
                    reportMalformed(line);
                    return;
                }
                String value = cache.get(line.substring(firstSpace + 1));
                out.println(value == null ? "NULL" : value);
            }
            case "DEL" -> {
                if (firstSpace < 0) {
                    reportMalformed(line);
                    return;
                }
                out.println(cache.remove(line.substring(firstSpace + 1)) ? 1 : 0);
            }
            case "SIZE" -> out.println(cache.size());
            case "" -> { } // tolerate blank lines
            default -> reportMalformed(line);
        }
    }

    private static String stripCarriageReturn(String line) {
        return line.endsWith("\r") ? line.substring(0, line.length() - 1) : line;
    }

    private static void reportMalformed(String line) {
        System.err.println("skipping malformed command: " + line);
    }
}
