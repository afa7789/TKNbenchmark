using System.Text.Json.Serialization;

namespace KvHttp;

[JsonSerializable(typeof(string[]))]
internal sealed partial class KvJsonContext : JsonSerializerContext;
