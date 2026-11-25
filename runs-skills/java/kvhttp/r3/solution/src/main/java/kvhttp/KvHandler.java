package kvhttp;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/// Routes HTTP requests to the key-value store.
final class KvHandler implements HttpHandler {

    static final int MAX_VALUE_BYTES = 1 << 20;

    private static final String KV_PREFIX = "/kv/";
    private static final Pattern KEY = Pattern.compile("[A-Za-z0-9_-]{1,64}");
    private static final byte[] NO_BODY = new byte[0];

    private final KeyValueStore store;

    KvHandler(KeyValueStore store) {
        this.store = store;
    }

    @Override
    public void handle(HttpExchange exchange) throws IOException {
        try (exchange) {
            String path = exchange.getRequestURI().getRawPath();
            String method = exchange.getRequestMethod();
            if (path.equals("/health")) {
                health(exchange, method);
            } else if (path.equals("/kv")) {
                list(exchange, method);
            } else if (path.startsWith(KV_PREFIX)) {
                item(exchange, method, path.substring(KV_PREFIX.length()));
            } else {
                send(exchange, 404, NO_BODY);
            }
        } catch (RuntimeException e) {
            System.err.println("request failed: " + e);
            throw e;
        }
    }

    private void health(HttpExchange exchange, String method) throws IOException {
        if (!method.equals("GET")) {
            methodNotAllowed(exchange, "GET");
            return;
        }
        send(exchange, 200, "ok".getBytes(StandardCharsets.US_ASCII));
    }

    private void list(HttpExchange exchange, String method) throws IOException {
        if (!method.equals("GET")) {
            methodNotAllowed(exchange, "GET");
            return;
        }
        exchange.getResponseHeaders().set("Content-Type", "application/json");
        send(exchange, 200, toJsonArray(store.keys()).getBytes(StandardCharsets.UTF_8));
    }

    private void item(HttpExchange exchange, String method, String key) throws IOException {
        if (!KEY.matcher(key).matches()) {
            send(exchange, 400, NO_BODY);
            return;
        }
        switch (method) {
            case "GET" -> {
                var value = store.get(key);
                if (value.isPresent()) {
                    exchange.getResponseHeaders().set("Content-Type", "application/octet-stream");
                    send(exchange, 200, value.get());
                } else {
                    send(exchange, 404, NO_BODY);
                }
            }
            case "PUT" -> {
                byte[] value = readBody(exchange);
                if (value == null) {
                    send(exchange, 413, NO_BODY);
                } else {
                    send(exchange, store.put(key, value) ? 201 : 200, NO_BODY);
                }
            }
            case "DELETE" -> send(exchange, store.delete(key) ? 204 : 404, NO_BODY);
            default -> methodNotAllowed(exchange, "GET, PUT, DELETE");
        }
    }

    /// Reads the request body, or returns `null` if it exceeds [#MAX_VALUE_BYTES].
    private static byte[] readBody(HttpExchange exchange) throws IOException {
        try (InputStream in = exchange.getRequestBody()) {
            byte[] body = in.readNBytes(MAX_VALUE_BYTES + 1);
            return body.length > MAX_VALUE_BYTES ? null : body;
        }
    }

    private static void methodNotAllowed(HttpExchange exchange, String allowed) throws IOException {
        exchange.getResponseHeaders().set("Allow", allowed);
        send(exchange, 405, NO_BODY);
    }

    private static void send(HttpExchange exchange, int status, byte[] body) throws IOException {
        // -1 tells HttpServer there is no body; it then emits Content-Length: 0 (or none for 204).
        exchange.sendResponseHeaders(status, body.length == 0 ? -1 : body.length);
        if (body.length > 0) {
            try (OutputStream out = exchange.getResponseBody()) {
                out.write(body);
            }
        }
    }

    /// Keys are restricted to `[A-Za-z0-9_-]`, so they never need JSON escaping.
    private static String toJsonArray(List<String> keys) {
        return keys.stream().map(k -> '"' + k + '"').collect(Collectors.joining(",", "[", "]"));
    }
}
