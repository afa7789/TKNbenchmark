package lru;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;

/**
 * Reads a capacity followed by cache commands from standard input and writes
 * command results to standard output, one per line.
 */
public final class Main {

    private static final int BUFFER_SIZE = 1 << 16;

    private Main() {
    }

    public static void main(String[] args) throws IOException {
        var in = new BufferedReader(
                new InputStreamReader(System.in, StandardCharsets.ISO_8859_1), BUFFER_SIZE);
        var out = new BufferedWriter(
                new OutputStreamWriter(System.out, StandardCharsets.ISO_8859_1), BUFFER_SIZE);
        run(in, out);
        out.flush();
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

    private static void execute(LruCache<String, String> cache, String line, Writer out)
            throws IOException {
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

    private static void writeLine(Writer out, String text) throws IOException {
        out.write(text);
        out.write('\n');
    }

    private static String stripCarriageReturn(String line) {
        return line.endsWith("\r") ? line.substring(0, line.length() - 1) : line;
    }
}
