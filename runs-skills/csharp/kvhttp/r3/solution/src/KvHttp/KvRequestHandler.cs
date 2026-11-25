using System.Buffers;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace KvHttp;

[JsonSerializable(typeof(string[]))]
internal sealed partial class AppJsonContext : JsonSerializerContext;

/// <summary>Dispatches requests for the kvhttp routes.</summary>
public sealed class KvRequestHandler(KeyValueStore store)
{
    public const int MaxValueBytes = 1024 * 1024;
    private const string KvPrefix = "/kv/";

    private static readonly SearchValues<char> KeyChars =
        SearchValues.Create("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-");

    public Task HandleAsync(HttpContext context)
    {
        ArgumentNullException.ThrowIfNull(context);
        string path = context.Request.Path.Value ?? "/";
        string method = context.Request.Method;

        if (path == "/health")
        {
            return HttpMethods.IsGet(method) ? WriteTextAsync(context, "ok") : Status(context, StatusCodes.Status405MethodNotAllowed);
        }

        if (path == "/kv")
        {
            return HttpMethods.IsGet(method) ? ListAsync(context) : Status(context, StatusCodes.Status405MethodNotAllowed);
        }

        if (path.StartsWith(KvPrefix, StringComparison.Ordinal))
        {
            string key = path[KvPrefix.Length..];
            if (!IsValidKey(key))
            {
                return Status(context, StatusCodes.Status400BadRequest);
            }

            if (HttpMethods.IsGet(method))
            {
                return GetAsync(context, key);
            }
            if (HttpMethods.IsPut(method))
            {
                return PutAsync(context, key);
            }
            if (HttpMethods.IsDelete(method))
            {
                return Status(context, store.Remove(key) ? StatusCodes.Status204NoContent : StatusCodes.Status404NotFound);
            }
            return Status(context, StatusCodes.Status405MethodNotAllowed);
        }

        return Status(context, StatusCodes.Status404NotFound);
    }

    public static bool IsValidKey(ReadOnlySpan<char> key) =>
        key.Length is >= 1 and <= 64 && !key.ContainsAnyExcept(KeyChars);

    private Task GetAsync(HttpContext context, string key)
    {
        if (!store.TryGet(key, out byte[] value))
        {
            return Status(context, StatusCodes.Status404NotFound);
        }
        context.Response.StatusCode = StatusCodes.Status200OK;
        context.Response.ContentType = "application/octet-stream";
        context.Response.ContentLength = value.Length;
        return context.Response.Body.WriteAsync(value, context.RequestAborted).AsTask();
    }

    private async Task PutAsync(HttpContext context, string key)
    {
        byte[]? value = await ReadBodyAsync(context.Request, context.RequestAborted);
        if (value is null)
        {
            await Status(context, StatusCodes.Status413PayloadTooLarge);
            return;
        }
        await Status(context, store.Put(key, value) ? StatusCodes.Status201Created : StatusCodes.Status200OK);
    }

    private Task ListAsync(HttpContext context)
    {
        byte[] json = JsonSerializer.SerializeToUtf8Bytes(store.SortedKeys(), AppJsonContext.Default.StringArray);
        context.Response.StatusCode = StatusCodes.Status200OK;
        context.Response.ContentType = "application/json";
        context.Response.ContentLength = json.Length;
        return context.Response.Body.WriteAsync(json, context.RequestAborted).AsTask();
    }

    /// <summary>Reads the whole body, or returns <c>null</c> if it exceeds <see cref="MaxValueBytes"/>.</summary>
    private static async Task<byte[]?> ReadBodyAsync(HttpRequest request, CancellationToken ct)
    {
        long? declared = request.ContentLength;
        if (declared > MaxValueBytes)
        {
            return null;
        }

        if (declared is long length)
        {
            byte[] exact = new byte[length];
            await request.Body.ReadExactlyAsync(exact, ct);
            return exact;
        }

        using var buffer = new MemoryStream();
        byte[] chunk = ArrayPool<byte>.Shared.Rent(81920);
        try
        {
            int read;
            while ((read = await request.Body.ReadAsync(chunk, ct)) > 0)
            {
                if (buffer.Length + read > MaxValueBytes)
                {
                    return null;
                }
                buffer.Write(chunk, 0, read);
            }
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(chunk);
        }
        return buffer.ToArray();
    }

    private static Task WriteTextAsync(HttpContext context, string text)
    {
        context.Response.StatusCode = StatusCodes.Status200OK;
        context.Response.ContentType = "text/plain; charset=utf-8";
        context.Response.ContentLength = System.Text.Encoding.UTF8.GetByteCount(text);
        return context.Response.WriteAsync(text, context.RequestAborted);
    }

    private static Task Status(HttpContext context, int statusCode)
    {
        context.Response.StatusCode = statusCode;
        if (statusCode != StatusCodes.Status204NoContent)
        {
            context.Response.ContentLength = 0;
        }
        return Task.CompletedTask;
    }
}
