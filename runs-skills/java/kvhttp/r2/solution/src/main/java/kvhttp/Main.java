package kvhttp;

import java.io.IOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;

/// Entry point: `app <port>` serves the key-value API on `127.0.0.1:<port>` until killed.
public final class Main {

    private Main() {}

    public static void main(String[] args) throws IOException {
        if (args.length != 1) {
            System.err.println("usage: app <port>");
            System.exit(2);
        }
        int port;
        try {
            port = Integer.parseInt(args[0]);
        } catch (NumberFormatException _) {
            port = -1;
        }
        if (port < 1 || port > 65535) {
            System.err.println("invalid port: " + args[0]);
            System.exit(2);
        }
        var address = new InetSocketAddress(InetAddress.getLoopbackAddress(), port);
        KvServer server = KvServer.start(address, new KeyValueStore());
        Runtime.getRuntime().addShutdownHook(Thread.ofPlatform().unstarted(server::stop));
    }
}
