package calc;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;

/**
 * Entry point: reads one expression per line from standard input and prints
 * its value or {@code error}. Blank lines produce no output.
 */
public final class Main {

    /** Generous stack so deeply nested expressions do not overflow the recursive parser. */
    private static final long STACK_SIZE_BYTES = 1L << 30;

    private Main() {
    }

    public static void main(String[] args) throws InterruptedException {
        Thread worker = new Thread(null, Main::run, "calc", STACK_SIZE_BYTES);
        worker.start();
        worker.join();
    }

    private static void run() {
        // ISO-8859-1 maps every byte to a char, so arbitrary input bytes never fail decoding;
        // any non-ASCII byte is simply an invalid token.
        try (BufferedReader in = new BufferedReader(
                     new InputStreamReader(System.in, StandardCharsets.ISO_8859_1), 1 << 16);
             PrintWriter out = new PrintWriter(new BufferedWriter(
                     new OutputStreamWriter(System.out, StandardCharsets.US_ASCII), 1 << 16))) {
            String line;
            while ((line = readLine(in)) != null) {
                if (!isBlank(line)) {
                    out.print(evaluate(line));
                    out.print('\n');
                }
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /**
     * Reads a line terminated by {@code '\n'} only (unlike {@link BufferedReader#readLine()},
     * a {@code '\r'} is kept so that it is rejected as an invalid character).
     *
     * @return the line without its terminator, or {@code null} at end of input
     */
    private static String readLine(BufferedReader in) throws IOException {
        StringBuilder sb = new StringBuilder();
        int c;
        while ((c = in.read()) != -1) {
            if (c == '\n') {
                return sb.toString();
            }
            sb.append((char) c);
        }
        return sb.isEmpty() ? null : sb.toString();
    }

    private static String evaluate(String line) {
        try {
            return Long.toString(Parser.evaluate(line));
        } catch (CalcException | StackOverflowError e) {
            return "error";
        }
    }

    private static boolean isBlank(String line) {
        for (int i = 0; i < line.length(); i++) {
            char c = line.charAt(i);
            if (c != ' ' && c != '\t') {
                return false;
            }
        }
        return true;
    }
}
