package wordfreq;

import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/// Reads standard input and prints the ten most frequent ASCII-letter words.
public final class Main {

    private static final int TOP = 10;
    private static final int READ_BUFFER = 1 << 16;

    private Main() {}

    public static void main(String[] args) throws IOException {
        WordCounter counter = count(System.in);
        try (Writer out = new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.US_ASCII))) {
            for (WordCounter.Entry e : counter.top(TOP)) {
                out.write(e.count() + " " + e.word() + "\n");
            }
        }
    }

    /// Tokenizes the stream into maximal runs of ASCII letters, folded to lowercase.
    static WordCounter count(InputStream in) throws IOException {
        WordCounter counter = new WordCounter();
        byte[] buf = new byte[READ_BUFFER];
        byte[] word = new byte[64];
        int wordLen = 0;
        int n;
        while ((n = in.read(buf)) > 0) {
            for (int i = 0; i < n; i++) {
                int b = buf[i];
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
