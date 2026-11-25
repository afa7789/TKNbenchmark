package kvhttp;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Pattern;

/// HTTP front end for a [KeyValueStore].
final class KvServer {

    static final int MAX_VALUE_BYTES = 1 << 20;

    private static final Pattern KEY = Pattern.compile("[A-Za-z0-9_-]{1,64}");
    private static final String KV_PREFIX = "/kv/";
    private static final int BACKLOG = 1024;

    private final HttpServer http;
    private final ExecutorService executor;
    private final KeyValueStore store;

    private KvServer(HttpServer http, ExecutorService executor, KeyValueStore store) {
        this.http = http;
        this.executor = executor;
        this.store = store;
    }

    static KvServer start(InetSocketAddress address, KeyValueStore store) throws IOException {
        HttpServer http = HttpServer.create(address, BACKLOG);
        ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor();
        var server = new KvServer(http, executor, store);
        http.createContext("/", server::handle);
        http.setExecutor(executor);
        http.start();
        return server;
    }

    void stop() {
        http.stop(0);
        executor.close();
    }

    private void handle(HttpExchange exchange) throws IOException {
        try (exchange) {
            Response response;
            try {
                response = route(exchange);
            } catch (PayloadTooLargeException _) {
                response = Response.status(413);
            }
            send(exchange, response);
        }
    }

    private Response route(HttpExchange exchange) throws IOException {
        String method = exchange.getRequestMethod();
        String path = exchange.getRequestURI().getRawPath();
        if (path == null) {
            return Response.status(404);
        }
        if (path.equals("/health")) {
            return method.equals("GET") ? Response.text(200, "ok") : Response.status(405);
        }
        if (path.equals("/kv")) {
            return method.equals("GET") ? Response.json(200, toJsonArray(store.keys())) : Response.status(405);
        }
        if (path.startsWith(KV_PREFIX)) {
            String key = path.substring(KV_PREFIX.length());
            if (!KEY.matcher(key).matches()) {
                return Response.status(400);
            }
            return switch (method) {
                case "GET" -> store.get(key)
                        .map(value -> Response.bytes(200, value))
                        .orElseGet(() -> Response.status(404));
                case "PUT" -> Response.status(store.put(key, readBody(exchange)) ? 201 : 200);
                case "DELETE" -> Response.status(store.delete(key) ? 204 : 404);
                default -> Response.status(405);
            };
        }
        return Response.status(404);
    }

    private static byte[] readBody(HttpExchange exchange) throws IOException {
        String declared = exchange.getRequestHeaders().getFirst("Content-Length");
        if (declared != null) {
            try {
                if (Long.parseLong(declared.trim()) > MAX_VALUE_BYTES) {
                    throw new PayloadTooLargeException();
                }
            } catch (NumberFormatException _) {
                // Malformed lengths are rejected by HttpServer itself; fall through to the bounded read.
            }
        }
        InputStream in = exchange.getRequestBody();
        byte[] body = in.readNBytes(MAX_VALUE_BYTES + 1);
        if (body.length > MAX_VALUE_BYTES) {
            throw new PayloadTooLargeException();
        }
        return body;
    }

    private static void send(HttpExchange exchange, Response response) throws IOException {
        if (response.contentType() != null) {
            exchange.getResponseHeaders().set("Content-Type", response.contentType());
        }
        byte[] body = response.body();
        boolean noBody = body.length == 0 || response.status() == 204;
        exchange.sendResponseHeaders(response.status(), noBody ? -1 : body.length);
        if (!noBody) {
            try (OutputStream out = exchange.getResponseBody()) {
                out.write(body);
            }
        }
    }

    private static String toJsonArray(List<String> keys) {
        var json = new StringBuilder(keys.size() * 8 + 2).append('[');
        for (int i = 0; i < keys.size(); i++) {
            if (i > 0) {
                json.append(',');
            }
            // Keys are restricted to [A-Za-z0-9_-], so they never need escaping.
            json.append('"').append(keys.get(i)).append('"');
        }
        return json.append(']').toString();
    }

    private record Response(int status, String contentType, byte[] body) {

        private static final byte[] EMPTY = new byte[0];

        static Response status(int status) {
            return new Response(status, null, EMPTY);
        }

        static Response text(int status, String text) {
            return new Response(status, "text/plain; charset=utf-8", text.getBytes(StandardCharsets.UTF_8));
        }

        static Response json(int status, String json) {
            return new Response(status, "application/json", json.getBytes(StandardCharsets.UTF_8));
        }

        static Response bytes(int status, byte[] body) {
            return new Response(status, "application/octet-stream", body);
        }
    }

    private static final class PayloadTooLargeException extends RuntimeException {
        private static final long serialVersionUID = 1L;

        PayloadTooLargeException() {
            super(null, null, false, false);
        }
    }
}
