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

/** Routes requests for the key-value API. */
final class KvHandler implements HttpHandler {
    static final int MAX_VALUE_BYTES = 1 << 20;

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
                response = Response.empty(413);
            }
            send(exchange, response);
        }
    }

    private Response route(HttpExchange exchange) throws IOException {
        String method = exchange.getRequestMethod();
        String path = exchange.getRequestURI().getRawPath();

        if (path.equals("/health")) {
            return method.equals("GET")
                    ? Response.text(200, "ok")
                    : Response.empty(405);
        }
        if (path.equals("/kv")) {
            return method.equals("GET") ? listKeys() : Response.empty(405);
        }
        if (path.startsWith(KV_PREFIX)) {
            String key = path.substring(KV_PREFIX.length());
            if (!KEY.matcher(key).matches()) {
                return Response.empty(400);
            }
            return switch (method) {
                case "GET" -> store.get(key)
                        .map(value -> new Response(200, "application/octet-stream", value))
                        .orElseGet(() -> Response.empty(404));
                case "PUT" -> Response.empty(store.put(key, readBody(exchange)) ? 201 : 200);
                case "DELETE" -> Response.empty(store.delete(key) ? 204 : 404);
                default -> Response.empty(405);
            };
        }
        return Response.empty(404);
    }

    private Response listKeys() {
        List<String> keys = store.keys();
        // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is required.
        String json = keys.stream()
                .map(k -> '"' + k + '"')
                .collect(Collectors.joining(",", "[", "]"));
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
                // Let the server's own framing decide; the size cap below still applies.
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
        // A length of -1 tells HttpServer there is no body (it emits Content-Length: 0 where allowed).
        exchange.sendResponseHeaders(response.status(), body.length == 0 ? -1 : body.length);
        if (body.length > 0) {
            try (OutputStream out = exchange.getResponseBody()) {
                out.write(body);
            }
        }
    }

    private record Response(int status, String contentType, byte[] body) {
        static Response empty(int status) {
            return new Response(status, null, NO_BODY);
        }

        static Response text(int status, String text) {
            return new Response(status, "text/plain; charset=utf-8", text.getBytes(StandardCharsets.UTF_8));
        }
    }

    private static final class PayloadTooLargeException extends RuntimeException {
        PayloadTooLargeException() {
            super(null, null, false, false);
        }
    }
}
