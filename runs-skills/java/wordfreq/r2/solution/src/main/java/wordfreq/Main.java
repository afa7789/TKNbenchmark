package wordfreq;

import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;

/// Reads standard input and prints the ten most frequent ASCII words.
public final class Main {

  private static final int TOP_N = 10;
  private static final int BUFFER_SIZE = 1 << 16;

  private Main() {}

  public static void main(String[] args) throws IOException {
    WordCounter counter = count(System.in);
    var out = new PrintStream(new BufferedOutputStream(System.out), false, StandardCharsets.US_ASCII);
    for (WordCount wc : counter.top(TOP_N)) {
      out.print(wc);
      out.print('\n');
    }
    out.flush();
  }

  static WordCounter count(InputStream in) throws IOException {
    var counter = new WordCounter();
    byte[] buf = new byte[BUFFER_SIZE];
    int n;
    while ((n = in.read(buf)) != -1) {
      counter.accept(buf, 0, n);
    }
    counter.finish();
    return counter;
  }
}
