package wordfreq;

import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** Reads standard input and prints the ten most frequent ASCII words. */
public final class Main {

    private static final int TOP_N = 10;
    private static final int BUFFER_SIZE = 1 << 16;

    private Main() {}

    public static void main(String[] args) throws IOException {
        WordCounter counter = count(System.in);
        PrintStream out = new PrintStream(new BufferedOutputStream(System.out), false, StandardCharsets.US_ASCII);
        for (WordCounter.Entry e : counter.top(TOP_N)) {
            out.print(e.count());
            out.print(' ');
            out.print(e.word());
            out.print('\n');
        }
        out.flush();
    }

    static WordCounter count(InputStream in) throws IOException {
        WordCounter counter = new WordCounter();
        byte[] buf = new byte[BUFFER_SIZE];
        byte[] word = new byte[64];
        int wordLen = 0;
        int hash = 0;
        int n;
        while ((n = in.read(buf)) > 0) {
            for (int i = 0; i < n; i++) {
                int b = buf[i];
                // Fold to lowercase: 'A'..'Z' | 0x20 -> 'a'..'z'.
                int lower = b | 0x20;
                if (lower >= 'a' && lower <= 'z') {
                    if (wordLen == word.length) {
                        word = Arrays.copyOf(word, word.length * 2);
                    }
                    word[wordLen++] = (byte) lower;
                    hash = hash * 31 + lower;
                } else if (wordLen > 0) {
                    counter.add(word, 0, wordLen, hash);
                    wordLen = 0;
                    hash = 0;
                }
            }
        }
        if (wordLen > 0) {
            counter.add(word, 0, wordLen, hash);
        }
        return counter;
    }
}
