package calc;

import java.io.BufferedInputStream;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStreamWriter;
import java.io.UncheckedIOException;
import java.io.Writer;
import java.nio.charset.StandardCharsets;

/// Reads one expression per line from standard input and prints its value or `error`.
public final class Main {
    /// Stack size for the worker thread, so deeply nested expressions do not overflow.
    private static final long STACK_SIZE = 1L << 30;

    private Main() {
    }

    public static void main(String[] args) throws InterruptedException {
        Thread worker = new Thread(null, Main::run, "calc", STACK_SIZE);
        worker.start();
        worker.join();
    }

    private static void run() {
        try (InputStream in = new BufferedInputStream(System.in, 1 << 16);
                Writer out = new BufferedWriter(
                        new OutputStreamWriter(System.out, StandardCharsets.ISO_8859_1), 1 << 16)) {
            String line;
            while ((line = readLine(in)) != null) {
                if (isBlank(line)) {
                    continue;
                }
                out.write(evaluateLine(line));
                out.write('\n');
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /// Reads the next line terminated by `'\n'` (only), or the unterminated tail of the input.
    /// Bytes map one-to-one onto ISO-8859-1 chars, so arbitrary input never fails decoding;
    /// a `'\r'` stays in the line and is rejected by the evaluator like any foreign character.
    ///
    /// @return the line without its terminator, or `null` at end of input
    private static String readLine(InputStream in) throws IOException {
        StringBuilder line = new StringBuilder();
        int b;
        while ((b = in.read()) != -1) {
            if (b == '\n') {
                return line.toString();
            }
            line.append((char) b);
        }
        return line.isEmpty() ? null : line.toString();
    }

    private static String evaluateLine(String line) {
        try {
            return Long.toString(Evaluator.evaluate(line));
        } catch (EvaluationException | StackOverflowError _) {
            return "error";
        }
    }

    private static boolean isBlank(String line) {
        for (int i = 0; i < line.length(); i++) {
            if (!Evaluator.isBlank(line.charAt(i))) {
                return false;
            }
        }
        return true;
    }
}
