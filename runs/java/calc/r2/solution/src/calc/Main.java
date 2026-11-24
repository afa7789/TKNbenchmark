package calc;

import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** Reads one expression per line from standard input and prints its value or {@code error}. */
public final class Main {
    /** Deeply nested parentheses recurse; run on a thread with a generous stack. */
    private static final long STACK_SIZE = 1L << 30;
    private static final byte[] ERROR = "error\n".getBytes(StandardCharsets.US_ASCII);

    private Main() {
    }

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
            System.exit(1);
        }
    }

    static void run(InputStream in, PrintStream stdout) throws IOException {
        OutputStream out = new BufferedOutputStream(stdout, 1 << 16);
        LineReader reader = new LineReader(in);
        byte[] line;
        while ((line = reader.next()) != null) {
            int length = reader.length();
            if (isBlank(line, length)) {
                continue;
            }
            byte[] result;
            try {
                result = (Evaluator.evaluate(line, 0, length) + "\n").getBytes(StandardCharsets.US_ASCII);
            } catch (EvaluationException | StackOverflowError e) {
                result = ERROR;
            }
            out.write(result);
        }
        out.flush();
    }

    private static boolean isBlank(byte[] line, int length) {
        for (int i = 0; i < length; i++) {
            if (!Evaluator.isBlank(line[i])) {
                return false;
            }
        }
        return true;
    }

    /** Minimal buffered reader that splits a byte stream on {@code '\n'}, reusing one line buffer. */
    private static final class LineReader {
        private final InputStream in;
        private final byte[] buffer = new byte[1 << 16];
        private int bufferPos;
        private int bufferLimit;
        private byte[] line = new byte[256];
        private int lineLength;

        LineReader(InputStream in) {
            this.in = in;
        }

        /** Returns the buffer holding the next line (see {@link #length()}), or null at end of input. */
        byte[] next() throws IOException {
            lineLength = 0;
            boolean sawAny = false;
            while (true) {
                if (bufferPos == bufferLimit) {
                    bufferLimit = in.read(buffer);
                    bufferPos = 0;
                    if (bufferLimit <= 0) {
                        bufferLimit = 0;
                        return sawAny ? line : null;
                    }
                }
                sawAny = true;
                int start = bufferPos;
                while (bufferPos < bufferLimit && buffer[bufferPos] != '\n') {
                    bufferPos++;
                }
                append(start, bufferPos);
                if (bufferPos < bufferLimit) {
                    bufferPos++; // consume '\n'
                    return line;
                }
            }
        }

        int length() {
            return lineLength;
        }

        private void append(int from, int to) {
            int count = to - from;
            if (lineLength + count > line.length) {
                line = Arrays.copyOf(line, Math.max(line.length * 2, lineLength + count));
            }
            System.arraycopy(buffer, from, line, lineLength, count);
            lineLength += count;
        }
    }
}
