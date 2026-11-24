package calc;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.util.Optional;

/**
 * Command-line entry point: evaluates one expression per line of standard input
 * and prints its value, or {@code error}.
 */
public final class Main {

    /** Deeply nested expressions are parsed recursively, so give the worker a generous stack. */
    private static final long STACK_SIZE_BYTES = 1L << 30;

    private Main() {
    }

    public static void main(String[] args) throws InterruptedException {
        Throwable[] failure = new Throwable[1];
        Thread worker = new Thread(null, () -> {
            try {
                run(System.in, System.out);
            } catch (IOException e) {
                failure[0] = e;
            }
        }, "calc", STACK_SIZE_BYTES);
        worker.start();
        worker.join();
        if (failure[0] != null) {
            System.err.println("calc: " + failure[0].getMessage());
        }
    }

    static void run(InputStream rawIn, OutputStream rawOut) throws IOException {
        InputStream in = new BufferedInputStream(rawIn, 1 << 16);
        PrintStream out = new PrintStream(new BufferedOutputStream(rawOut, 1 << 16), false, StandardCharsets.US_ASCII);
        ByteArrayOutputStream line = new ByteArrayOutputStream(256);
        int b;
        while ((b = in.read()) != -1) {
            if (b == '\n') {
                emit(line, out);
                line.reset();
            } else {
                line.write(b);
            }
        }
        if (line.size() > 0) {
            emit(line, out);
        }
        out.flush();
    }

    private static void emit(ByteArrayOutputStream line, PrintStream out) {
        byte[] bytes = line.toByteArray();
        if (Evaluator.isBlank(bytes)) {
            return;
        }
        Optional<Long> value = Evaluator.evaluate(bytes);
        out.println(value.map(String::valueOf).orElse("error"));
    }
}
