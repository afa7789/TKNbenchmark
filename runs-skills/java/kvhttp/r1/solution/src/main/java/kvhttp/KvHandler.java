package kvhttp;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.regex.Pattern;

/// Routes requests for the key-value API.
final class KvHandler implements HttpHandler {
  static final int MAX_VALUE_BYTES = 1 << 20;

  private static final String KV_PREFIX = "/kv/";
  private static final Pattern KEY = Pattern.compile("[A-Za-z0-9_-]{1,64}");
  private static final byte[] EMPTY = new byte[0];

  private final KvStore store;

  KvHandler(KvStore store) {
    this.store = store;
  }

  @Override
  public void handle(HttpExchange exchange) throws IOException {
    try (exchange) {
      route(exchange);
    } catch (RuntimeException e) {
      System.err.println("request failed: " + e);
      throw e;
    }
  }

  private void route(HttpExchange ex) throws IOException {
    String path = ex.getRequestURI().getRawPath();
    String method = ex.getRequestMethod();

    if ("/health".equals(path)) {
      if (!"GET".equals(method)) {
        sendEmpty(ex, 405, "GET");
        return;
      }
      send(ex, 200, "text/plain; charset=utf-8", "ok".getBytes(StandardCharsets.US_ASCII));
    } else if ("/kv".equals(path)) {
      if (!"GET".equals(method)) {
        sendEmpty(ex, 405, "GET");
        return;
      }
      send(ex, 200, "application/json", toJson(store.keys()));
    } else if (path != null && path.startsWith(KV_PREFIX)) {
      handleKey(ex, method, path.substring(KV_PREFIX.length()));
    } else {
      sendEmpty(ex, 404, null);
    }
  }

  private void handleKey(HttpExchange ex, String method, String key) throws IOException {
    if (!KEY.matcher(key).matches()) {
      sendEmpty(ex, 400, null);
      return;
    }
    switch (method) {
      case "GET" -> {
        var value = store.get(key);
        if (value.isPresent()) {
          send(ex, 200, "application/octet-stream", value.get());
        } else {
          sendEmpty(ex, 404, null);
        }
      }
      case "PUT" -> {
        byte[] body = readBody(ex);
        if (body == null) {
          sendEmpty(ex, 413, null);
          return;
        }
        sendEmpty(ex, store.put(key, body) ? 201 : 200, null);
      }
      case "DELETE" -> sendEmpty(ex, store.delete(key) ? 204 : 404, null);
      default -> sendEmpty(ex, 405, "GET, PUT, DELETE");
    }
  }

  /// Reads the request body, or returns null if it exceeds the value size limit.
  private static byte[] readBody(HttpExchange ex) throws IOException {
    String declared = ex.getRequestHeaders().getFirst("Content-Length");
    if (declared != null) {
      try {
        if (Long.parseLong(declared.trim()) > MAX_VALUE_BYTES) {
          return null;
        }
      } catch (NumberFormatException _) {
        // The server itself rejects malformed lengths; fall through and read what arrives.
      }
    }
    try (InputStream in = ex.getRequestBody()) {
      byte[] body = in.readNBytes(MAX_VALUE_BYTES + 1);
      return body.length > MAX_VALUE_BYTES ? null : body;
    }
  }

  private static byte[] toJson(List<String> keys) {
    // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is required.
    var sb = new StringBuilder(keys.size() * 8 + 2).append('[');
    for (int i = 0; i < keys.size(); i++) {
      if (i > 0) {
        sb.append(',');
      }
      sb.append('"').append(keys.get(i)).append('"');
    }
    return sb.append(']').toString().getBytes(StandardCharsets.US_ASCII);
  }

  private static void send(HttpExchange ex, int status, String contentType, byte[] body)
      throws IOException {
    ex.getResponseHeaders().set("Content-Type", contentType);
    ex.sendResponseHeaders(status, body.length == 0 ? -1 : body.length);
    if (body.length > 0) {
      try (OutputStream out = ex.getResponseBody()) {
        out.write(body);
      }
    }
  }

  private static void sendEmpty(HttpExchange ex, int status, String allow) throws IOException {
    if (allow != null) {
      ex.getResponseHeaders().set("Allow", allow);
    }
    ex.sendResponseHeaders(status, -1);
    ex.getResponseBody().close();
  }
}
