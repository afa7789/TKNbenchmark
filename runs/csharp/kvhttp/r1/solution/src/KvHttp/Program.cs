using System.Net;
using KvHttp;

if (args.Length != 1 || !int.TryParse(args[0], out var port) || port is < 1 or > 65535)
{
    Console.Error.WriteLine("usage: app <port>");
    return 2;
}

var builder = WebApplication.CreateSlimBuilder();
builder.Logging.ClearProviders();
builder.WebHost.ConfigureKestrel(options =>
{
    options.Listen(IPAddress.Loopback, port);
    options.AddServerHeader = false;
    options.Limits.MaxRequestBodySize = KvHandler.MaxValueBytes + 1;
    options.Limits.MaxConcurrentConnections = null;
});

builder.Services.AddSingleton<KeyValueStore>();
builder.Services.AddSingleton<KvHandler>();

var app = builder.Build();
var handler = app.Services.GetRequiredService<KvHandler>();
app.Run(handler.HandleAsync);

await app.RunAsync();
return 0;
