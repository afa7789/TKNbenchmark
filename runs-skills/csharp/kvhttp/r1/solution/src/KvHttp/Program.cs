using System.Globalization;
using System.Net;
using KvHttp;

if (args.Length != 1 || !int.TryParse(args[0], NumberStyles.None, CultureInfo.InvariantCulture, out int port) || port is < 1 or > 65535)
{
    await Console.Error.WriteLineAsync("usage: app <port>").ConfigureAwait(false);
    return 2;
}

WebApplicationBuilder builder = WebApplication.CreateSlimBuilder(args);
builder.Logging.ClearProviders();
builder.WebHost.ConfigureKestrel(options =>
{
    options.Listen(IPAddress.Loopback, port);
    options.AddServerHeader = false;
    options.Limits.MaxRequestBodySize = KvRequestHandler.MaxValueBytes;
    options.Limits.MaxConcurrentConnections = null;
});
builder.Services.AddSingleton<KeyValueStore>();
builder.Services.AddSingleton<KvRequestHandler>();

await using WebApplication app = builder.Build();
KvRequestHandler handler = app.Services.GetRequiredService<KvRequestHandler>();
app.Run(handler.HandleAsync);

await app.RunAsync().ConfigureAwait(false);
return 0;
