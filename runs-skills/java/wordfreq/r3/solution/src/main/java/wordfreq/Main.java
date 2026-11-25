package wordfreq;

import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/// Reads standard input and prints the 10 most frequent ASCII-letter words.
public final class Main {

    private static final int TOP = 10;
    private static final int CHUNK = 1 << 16;

    private Main() {}

    public static void main(String[] args) throws IOException {
        WordCounter counter = count(System.in);
        OutputStream out = new BufferedOutputStream(System.out);
        for (WordCount wc : counter.top(TOP)) {
            out.write(Long.toString(wc.count()).getBytes(StandardCharsets.US_ASCII));
            out.write(' ');
            out.write(wc.word());
            out.write('\n');
        }
        out.flush();
    }

    /// Tokenizes the stream into maximal runs of ASCII letters, folded to lowercase.
    static WordCounter count(InputStream in) throws IOException {
        WordCounter counter = new WordCounter();
        byte[] chunk = new byte[CHUNK];
        byte[] word = new byte[64];
        int len = 0;
        int hash = 0;
        int n;
        while ((n = in.read(chunk)) != -1) {
            for (int i = 0; i < n; i++) {
                int b = chunk[i];
                int lower = b | 0x20;
                if (lower >= 'a' && lower <= 'z') {
                    if (len == word.length) {
                        word = Arrays.copyOf(word, len * 2);
                    }
                    word[len++] = (byte) lower;
                    hash = hash * 31 + lower;
                } else if (len > 0) {
                    counter.add(word, len, WordCounter.finishHash(hash));
                    len = 0;
                    hash = 0;
                }
            }
        }
        if (len > 0) {
            counter.add(word, len, WordCounter.finishHash(hash));
        }
        return counter;
    }
}
