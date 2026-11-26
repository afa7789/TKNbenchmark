import { App } from "./app.ts";
import { Server } from "./server.ts";
import { Store } from "./store.ts";

async function main(argv: readonly string[]): Promise<number> {
  const [portArg] = argv;
  if (argv.length !== 1 || portArg === undefined || !/^[0-9]+$/.test(portArg)) {
    console.error("usage: app <port>");
    return 2;
  }
  const server = new Server(new App(new Store()));
  await server.listen("127.0.0.1", Number(portArg));
  return 0;
}

main(process.argv.slice(2)).then(
  (code) => {
    if (code !== 0) process.exitCode = code;
  },
  (err: unknown) => {
    console.error(err);
    process.exitCode = 1;
  },
);
