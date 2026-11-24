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
    options.AddServerHeader = false;
    options.Limits.MaxRequestBodySize = KvEndpoints.MaxValueBytes + 1;
    options.Limits.MaxConcurrentConnections = null;
    options.Listen(IPAddress.Loopback, port);
});
builder.Services.AddSingleton<KvStore>();

var app = builder.Build();
var store = app.Services.GetRequiredService<KvStore>();
app.Run(context => KvEndpoints.HandleAsync(context, store));

await app.RunAsync();
return 0;
