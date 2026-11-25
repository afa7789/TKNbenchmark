package calc;

import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;

/// Reads one expression per line from standard input and prints its value or `error`.
public final class Main {
    /// Deeply nested parentheses recurse; give the evaluator a generous stack.
    private static final long STACK_SIZE = 1L << 30;
    private static final byte[] ERROR = "error\n".getBytes(StandardCharsets.US_ASCII);

    private Main() {}

    public static void main(String[] args) throws Exception {
        Throwable[] failure = new Throwable[1];
        Thread worker = new Thread(null, () -> {
            try {
                run(System.in, System.out);
            } catch (Throwable t) {
                failure[0] = t;
            }
        }, "calc", STACK_SIZE);
        worker.start();
        worker.join();
        if (failure[0] != null) {
            failure[0].printStackTrace();
        }
    }

    static void run(InputStream in, OutputStream rawOut) {
        try {
            byte[] data = in.readAllBytes();
            OutputStream out = new BufferedOutputStream(rawOut, 1 << 16);
            int start = 0;
            while (start < data.length) {
                int newline = indexOf(data, (byte) '\n', start);
                int end = newline < 0 ? data.length : newline;
                processLine(data, start, end, out);
                start = end + 1;
            }
            out.flush();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static void processLine(byte[] data, int start, int end, OutputStream out) throws IOException {
        if (isBlank(data, start, end)) {
            return;
        }
        byte[] result;
        try {
            result = (Long.toString(Evaluator.evaluate(data, start, end)) + '\n')
                    .getBytes(StandardCharsets.US_ASCII);
        } catch (EvaluationException | StackOverflowError _) {
            result = ERROR;
        }
        out.write(result);
    }

    private static boolean isBlank(byte[] data, int start, int end) {
        for (int i = start; i < end; i++) {
            if (data[i] != ' ' && data[i] != '\t') {
                return false;
            }
        }
        return true;
    }

    private static int indexOf(byte[] data, byte target, int from) {
        for (int i = from; i < data.length; i++) {
            if (data[i] == target) {
                return i;
            }
        }
        return -1;
    }
}
