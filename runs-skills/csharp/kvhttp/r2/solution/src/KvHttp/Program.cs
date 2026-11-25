using System.Globalization;
using System.Net;
using KvHttp;

if (args.Length != 1 || !int.TryParse(args[0], NumberStyles.None, CultureInfo.InvariantCulture, out int port) || port is < 1 or > 65535)
{
    await Console.Error.WriteLineAsync("usage: app <port>");
    return 2;
}

var builder = WebApplication.CreateSlimBuilder();
builder.Logging.ClearProviders();
builder.WebHost.ConfigureKestrel(options =>
{
    options.Listen(IPAddress.Loopback, port);
    options.AddServerHeader = false;
    options.Limits.MaxRequestBodySize = KvRequestHandler.MaxValueBytes;
});
builder.Services.AddSingleton<KeyValueStore>();
builder.Services.AddSingleton<KvRequestHandler>();

var app = builder.Build();
var handler = app.Services.GetRequiredService<KvRequestHandler>();
app.Run(handler.HandleAsync);

await app.RunAsync();
return 0;
