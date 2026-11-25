package wordfreq;

import java.util.Comparator;

/// A word together with the number of times it occurred.
record WordCount(String word, long count) {

  /// Orders by count descending, then by word ascending (byte order for ASCII words).
  static final Comparator<WordCount> BY_FREQUENCY =
      Comparator.comparingLong(WordCount::count).reversed().thenComparing(WordCount::word);

  @Override
  public String toString() {
    return count + " " + word;
  }
}
