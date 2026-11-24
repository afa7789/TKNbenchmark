package kvhttp;

import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.util.concurrent.Executors;

/** Entry point: {@code app <port>} serves the key-value API on 127.0.0.1. */
public final class Main {
    private static final int BACKLOG = 1024;

    private Main() {}

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

        var address = new InetSocketAddress(InetAddress.getLoopbackAddress(), port);
        HttpServer server = HttpServer.create(address, BACKLOG);
        server.createContext("/", new KvHandler(new KvStore()));
        server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
        server.start();
    }
}
