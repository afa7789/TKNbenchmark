package wordfreq;

import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** Prints the ten most frequent ASCII-letter words read from standard input. */
public final class Main {

    private static final int TOP_N = 10;
    private static final int READ_BUFFER_SIZE = 1 << 16;

    private Main() {
    }

    public static void main(String[] args) throws IOException {
        WordCounter counter = count(System.in);
        StringBuilder out = new StringBuilder();
        for (WordCounter.Entry entry : counter.top(TOP_N)) {
            out.append(entry.count()).append(' ').append(entry.word()).append('\n');
        }
        PrintStream stdout = new PrintStream(System.out, false, StandardCharsets.ISO_8859_1);
        stdout.print(out);
        stdout.flush();
    }

    /** Tokenizes the stream into lowercase words and counts them. */
    static WordCounter count(InputStream in) throws IOException {
        WordCounter counter = new WordCounter();
        byte[] buffer = new byte[READ_BUFFER_SIZE];
        byte[] word = new byte[64];
        int wordLength = 0;
        int read;
        while ((read = in.read(buffer)) != -1) {
            for (int i = 0; i < read; i++) {
                int b = buffer[i];
                int lower = b | 0x20;
                if (lower >= 'a' && lower <= 'z') {
                    if (wordLength == word.length) {
                        word = Arrays.copyOf(word, word.length * 2);
                    }
                    word[wordLength++] = (byte) lower;
                } else if (wordLength > 0) {
                    counter.add(word, wordLength);
                    wordLength = 0;
                }
            }
        }
        if (wordLength > 0) {
            counter.add(word, wordLength);
        }
        return counter;
    }
}
