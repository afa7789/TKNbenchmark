package kvhttp;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Set;
import java.util.function.Supplier;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/** Routes and serves all requests for the key-value HTTP API. */
final class KvHandler implements HttpHandler {

    static final int MAX_VALUE_BYTES = 1 << 20;

    private static final Logger LOG = Logger.getLogger(KvHandler.class.getName());
    private static final Pattern KEY = Pattern.compile("[A-Za-z0-9_-]{1,64}");
    private static final String KV_PREFIX = "/kv/";
    private static final byte[] NO_BODY = new byte[0];

    private final KvStore store;

    KvHandler(KvStore store) {
        this.store = store;
    }

    @Override
    public void handle(HttpExchange exchange) throws IOException {
        try (exchange) {
            Response response;
            try {
                response = route(exchange);
            } catch (PayloadTooLargeException e) {
                response = Response.status(413);
            } catch (RuntimeException e) {
                LOG.log(Level.WARNING, "Unhandled error serving request", e);
                response = Response.status(500);
            }
            send(exchange, response);
        }
    }

    private Response route(HttpExchange exchange) throws IOException {
        String method = exchange.getRequestMethod();
        String path = exchange.getRequestURI().getRawPath();

        if (path.equals("/health")) {
            return requireMethod(method, Set.of("GET"), () -> Response.text(200, "ok"));
        }
        if (path.equals("/kv")) {
            return requireMethod(method, Set.of("GET"), this::listKeys);
        }
        if (path.startsWith(KV_PREFIX)) {
            String key = path.substring(KV_PREFIX.length());
            if (!KEY.matcher(key).matches()) {
                return Response.status(400);
            }
            return switch (method) {
                case "GET" -> store.get(key)
                        .map(value -> new Response(200, "application/octet-stream", value))
                        .orElseGet(() -> Response.status(404));
                case "PUT" -> Response.status(store.put(key, readBody(exchange)) ? 201 : 200);
                case "DELETE" -> Response.status(store.delete(key) ? 204 : 404);
                default -> Response.status(405);
            };
        }
        return Response.status(404);
    }

    private static Response requireMethod(String method, Set<String> allowed, Supplier<Response> action) {
        return allowed.contains(method) ? action.get() : Response.status(405);
    }

    private Response listKeys() {
        List<String> keys = store.keys();
        // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is required.
        String json = keys.stream().collect(Collectors.joining("\",\"", keys.isEmpty() ? "[" : "[\"", keys.isEmpty() ? "]" : "\"]"));
        return new Response(200, "application/json", json.getBytes(StandardCharsets.UTF_8));
    }

    private static byte[] readBody(HttpExchange exchange) throws IOException {
        String declared = exchange.getRequestHeaders().getFirst("Content-Length");
        if (declared != null) {
            try {
                if (Long.parseLong(declared.trim()) > MAX_VALUE_BYTES) {
                    throw new PayloadTooLargeException();
                }
            } catch (NumberFormatException ignored) {
                // Let the HTTP server's own framing decide; the read below still enforces the limit.
            }
        }
        try (InputStream in = exchange.getRequestBody()) {
            byte[] body = in.readNBytes(MAX_VALUE_BYTES + 1);
            if (body.length > MAX_VALUE_BYTES) {
                throw new PayloadTooLargeException();
            }
            return body;
        }
    }

    private static void send(HttpExchange exchange, Response response) throws IOException {
        if (response.contentType() != null) {
            exchange.getResponseHeaders().set("Content-Type", response.contentType());
        }
        byte[] body = response.body();
        boolean bodyForbidden = response.status() == 204 || "HEAD".equals(exchange.getRequestMethod());
        if (bodyForbidden || body.length == 0) {
            // -1 tells HttpServer there is no body; it emits Content-Length: 0 where permitted.
            exchange.sendResponseHeaders(response.status(), -1);
            return;
        }
        exchange.sendResponseHeaders(response.status(), body.length);
        try (OutputStream out = exchange.getResponseBody()) {
            out.write(body);
        }
    }

    private record Response(int status, String contentType, byte[] body) {
        static Response status(int status) {
            return new Response(status, null, NO_BODY);
        }

        static Response text(int status, String text) {
            return new Response(status, "text/plain; charset=utf-8", text.getBytes(StandardCharsets.UTF_8));
        }
    }

    private static final class PayloadTooLargeException extends RuntimeException {
        private static final long serialVersionUID = 1L;

        PayloadTooLargeException() {
            super(null, null, false, false);
        }
    }
}
