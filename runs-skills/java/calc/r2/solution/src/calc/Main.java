package calc;

import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/// Reads one expression per line from standard input and prints its value or `error`.
public final class Main {
    /// Deeply nested input recurses deeply; run on a thread with a generous stack.
    private static final long STACK_BYTES = 1L << 30;

    private Main() {}

    public static void main(String[] args) throws Exception {
        Throwable[] failure = new Throwable[1];
        Thread worker = new Thread(null, () -> {
            try {
                run();
            } catch (IOException e) {
                failure[0] = e;
            }
        }, "calc", STACK_BYTES);
        worker.start();
        worker.join();
        if (failure[0] != null) {
            System.err.println("calc: " + failure[0].getMessage());
            System.exit(1);
        }
    }

    private static void run() throws IOException {
        byte[] input = System.in.readAllBytes();
        OutputStream out = new BufferedOutputStream(new FileOutputStream(FileDescriptor.out), 1 << 16);
        int lineStart = 0;
        while (lineStart < input.length) {
            int lineEnd = lineStart;
            while (lineEnd < input.length && input[lineEnd] != '\n') {
                lineEnd++;
            }
            if (!isBlank(input, lineStart, lineEnd)) {
                out.write(evaluateLine(input, lineStart, lineEnd).getBytes(StandardCharsets.US_ASCII));
                out.write('\n');
            }
            lineStart = lineEnd + 1;
        }
        out.flush();
    }

    private static String evaluateLine(byte[] input, int start, int end) {
        try {
            return Long.toString(Evaluator.evaluate(input, start, end));
        } catch (EvaluationException | StackOverflowError e) {
            return "error";
        }
    }

    private static boolean isBlank(byte[] buf, int start, int end) {
        for (int i = start; i < end; i++) {
            if (buf[i] != ' ' && buf[i] != '\t') {
                return false;
            }
        }
        return true;
    }
}
