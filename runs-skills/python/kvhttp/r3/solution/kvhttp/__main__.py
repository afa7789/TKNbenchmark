"""Entry point: ``python -m kvhttp <port>``."""

import argparse
import asyncio
import contextlib
import logging

from kvhttp.server import serve


def main() -> None:
    parser = argparse.ArgumentParser(prog="kvhttp", description="In-memory KV server")
    parser.add_argument("port", type=int, help="TCP port to listen on")
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    if not 0 < args.port < 65536:
        parser.error("port must be between 1 and 65535")

    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(message)s")
    with contextlib.suppress(KeyboardInterrupt):
        asyncio.run(serve(args.host, args.port))


if __name__ == "__main__":
    main()
