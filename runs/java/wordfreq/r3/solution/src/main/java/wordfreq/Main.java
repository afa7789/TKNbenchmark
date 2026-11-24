package wordfreq;

import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** Prints the ten most frequent ASCII words read from standard input. */
public final class Main {

    private static final int TOP_N = 10;
    private static final int READ_BUFFER_SIZE = 1 << 16;

    private Main() {
    }

    public static void main(String[] args) throws IOException {
        WordCounter counter = count(System.in);
        try (PrintWriter out = new PrintWriter(new BufferedWriter(
                new OutputStreamWriter(System.out, StandardCharsets.US_ASCII)))) {
            for (WordCounter.WordCount wc : counter.top(TOP_N)) {
                out.print(wc.count());
                out.print(' ');
                out.print(wc.word());
                out.print('\n');
            }
        }
    }

    /** Tokenizes the stream into maximal runs of ASCII letters, folded to lowercase. */
    static WordCounter count(InputStream in) throws IOException {
        WordCounter counter = new WordCounter();
        byte[] chunk = new byte[READ_BUFFER_SIZE];
        byte[] word = new byte[64];
        int wordLen = 0;

        int n;
        while ((n = in.read(chunk)) != -1) {
            for (int i = 0; i < n; i++) {
                int b = chunk[i];
                int lower = b | 0x20;
                if (lower >= 'a' && lower <= 'z') {
                    if (wordLen == word.length) {
                        word = Arrays.copyOf(word, word.length * 2);
                    }
                    word[wordLen++] = (byte) lower;
                } else if (wordLen > 0) {
                    counter.add(word, wordLen);
                    wordLen = 0;
                }
            }
        }
        if (wordLen > 0) {
            counter.add(word, wordLen);
        }
        return counter;
    }
}
