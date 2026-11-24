package kvhttp;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.InputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ConcurrentNavigableMap;
import java.util.concurrent.ConcurrentSkipListMap;
import java.util.concurrent.Executors;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.regex.Pattern;

/** In-memory HTTP/1.1 key-value server. */
public final class KvServer {

    private static final Logger LOG = Logger.getLogger(KvServer.class.getName());
    private static final Pattern KEY = Pattern.compile("[A-Za-z0-9_-]{1,64}");
    private static final int MAX_VALUE_BYTES = 1 << 20;
    private static final String KV_PREFIX = "/kv/";
    private static final byte[] EMPTY = new byte[0];

    private final ConcurrentNavigableMap<String, byte[]> store = new ConcurrentSkipListMap<>();

    public static void main(String[] args) throws IOException {
        if (args.length != 1) {
            System.err.println("usage: app <port>");
            System.exit(2);
        }
        int port;
        try {
            port = Integer.parseInt(args[0]);
        } catch (NumberFormatException e) {
            System.err.println("invalid port: " + args[0]);
            System.exit(2);
            return;
        }
        new KvServer().start(port);
    }

    void start(int port) throws IOException {
        HttpServer server = HttpServer.create(
                new InetSocketAddress(InetAddress.getLoopbackAddress(), port), 1024);
        server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
        server.createContext("/", this::handle);
        server.start();
    }

    private void handle(HttpExchange exchange) throws IOException {
        try (exchange) {
            Response response;
            try {
                response = route(exchange);
            } catch (IOException e) {
                throw e;
            } catch (RuntimeException e) {
                LOG.log(Level.WARNING, "request failed", e);
                response = Response.status(500);
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
            return method.equals("GET") ? listKeys() : Response.status(405);
        }
        if (path.startsWith(KV_PREFIX)) {
            String key = path.substring(KV_PREFIX.length());
            if (!KEY.matcher(key).matches()) {
                return Response.status(400);
            }
            return switch (method) {
                case "GET" -> {
                    byte[] value = store.get(key);
                    yield value == null ? Response.status(404) : new Response(200, null, value);
                }
                case "PUT" -> put(exchange, key);
                case "DELETE" -> Response.status(store.remove(key) == null ? 404 : 204);
                default -> Response.status(405);
            };
        }
        return Response.status(404);
    }

    private Response put(HttpExchange exchange, String key) throws IOException {
        String declared = exchange.getRequestHeaders().getFirst("Content-Length");
        if (declared != null) {
            try {
                if (Long.parseLong(declared.trim()) > MAX_VALUE_BYTES) {
                    return Response.status(413);
                }
            } catch (NumberFormatException e) {
                return Response.status(400);
            }
        }
        byte[] value;
        try (InputStream in = exchange.getRequestBody()) {
            value = in.readNBytes(MAX_VALUE_BYTES + 1);
        }
        if (value.length > MAX_VALUE_BYTES) {
            return Response.status(413);
        }
        return Response.status(store.put(key, value) == null ? 201 : 200);
    }

    private Response listKeys() {
        StringBuilder json = new StringBuilder("[");
        boolean first = true;
        // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed.
        for (String key : store.keySet()) {
            if (!first) {
                json.append(',');
            }
            json.append('"').append(key).append('"');
            first = false;
        }
        json.append(']');
        return new Response(200, "application/json", json.toString().getBytes(StandardCharsets.UTF_8));
    }

    private static void send(HttpExchange exchange, Response response) throws IOException {
        if (response.contentType() != null) {
            exchange.getResponseHeaders().set("Content-Type", response.contentType());
        }
        exchange.getResponseHeaders().set("Connection", "close");
        byte[] body = response.body();
        if (response.status() == 204 || body.length == 0) {
            exchange.sendResponseHeaders(response.status(), -1);
        } else {
            exchange.sendResponseHeaders(response.status(), body.length);
            exchange.getResponseBody().write(body);
        }
    }

    private record Response(int status, String contentType, byte[] body) {
        static Response status(int status) {
            return new Response(status, null, EMPTY);
        }

        static Response text(int status, String text) {
            return new Response(status, "text/plain; charset=utf-8", text.getBytes(StandardCharsets.UTF_8));
        }
    }
}
