using System.Buffers;
using System.Text.Json;
using Microsoft.AspNetCore.Http.Features;

namespace KvHttp;

/// <summary>Routes and serves every request for the key-value API.</summary>
public sealed class KvRequestHandler(KeyValueStore store)
{
    public const int MaxValueBytes = 1024 * 1024;
    private const int MaxKeyLength = 64;
    private const string KeyPrefix = "/kv/";

    private static readonly SearchValues<char> KeyChars =
        SearchValues.Create("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-");

    private static readonly byte[] HealthBody = "ok"u8.ToArray();

    public Task HandleAsync(HttpContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        // Route on the raw request target so Kestrel's dot-segment normalization
        // and percent-decoding cannot turn an invalid key into a different path.
        string path = context.Features.Get<IHttpRequestFeature>()?.RawTarget ?? context.Request.Path.Value ?? "/";
        string method = context.Request.Method;

        if (path == "/health")
        {
            return HttpMethods.IsGet(method) ? WriteAsync(context, StatusCodes.Status200OK, HealthBody, "text/plain") : Status(context, StatusCodes.Status405MethodNotAllowed);
        }

        if (path == "/kv")
        {
            return HttpMethods.IsGet(method) ? ListAsync(context) : Status(context, StatusCodes.Status405MethodNotAllowed);
        }

        if (path.StartsWith(KeyPrefix, StringComparison.Ordinal))
        {
            string key = path[KeyPrefix.Length..];
            if (!IsValidKey(key))
            {
                return Status(context, StatusCodes.Status400BadRequest);
            }

            return method switch
            {
                _ when HttpMethods.IsGet(method) => GetAsync(context, key),
                _ when HttpMethods.IsPut(method) => PutAsync(context, key),
                _ when HttpMethods.IsDelete(method) => Status(context, store.Remove(key) ? StatusCodes.Status204NoContent : StatusCodes.Status404NotFound),
                _ => Status(context, StatusCodes.Status405MethodNotAllowed),
            };
        }

        return Status(context, StatusCodes.Status404NotFound);
    }

    private static bool IsValidKey(ReadOnlySpan<char> key) =>
        key.Length is > 0 and <= MaxKeyLength && !key.ContainsAnyExcept(KeyChars);

    private Task GetAsync(HttpContext context, string key) =>
        store.TryGet(key, out byte[] value)
            ? WriteAsync(context, StatusCodes.Status200OK, value, "application/octet-stream")
            : Status(context, StatusCodes.Status404NotFound);

    private async Task PutAsync(HttpContext context, string key)
    {
        long? declared = context.Request.ContentLength;
        if (declared > MaxValueBytes)
        {
            await Status(context, StatusCodes.Status413PayloadTooLarge);
            return;
        }

        byte[]? value = await ReadBodyAsync(context.Request, declared, context.RequestAborted);
        if (value is null)
        {
            await Status(context, StatusCodes.Status413PayloadTooLarge);
            return;
        }

        bool created = store.Put(key, value);
        await Status(context, created ? StatusCodes.Status201Created : StatusCodes.Status200OK);
    }

    /// <summary>Reads the whole request body, or returns <see langword="null"/> if it exceeds <see cref="MaxValueBytes"/>.</summary>
    private static async Task<byte[]?> ReadBodyAsync(HttpRequest request, long? declared, CancellationToken ct)
    {
        if (declared is long exact)
        {
            byte[] buffer = new byte[exact];
            await request.Body.ReadExactlyAsync(buffer, ct);
            return buffer;
        }

        // No Content-Length (e.g. chunked): read up to the limit.
        using var stream = new MemoryStream();
        byte[] chunk = ArrayPool<byte>.Shared.Rent(16 * 1024);
        try
        {
            int read;
            while ((read = await request.Body.ReadAsync(chunk, ct)) > 0)
            {
                if (stream.Length + read > MaxValueBytes)
                {
                    return null;
                }
                stream.Write(chunk, 0, read);
            }
        }
        catch (BadHttpRequestException ex) when (ex.StatusCode == StatusCodes.Status413PayloadTooLarge)
        {
            return null;
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(chunk);
        }
        return stream.ToArray();
    }

    private Task ListAsync(HttpContext context)
    {
        var buffer = new ArrayBufferWriter<byte>();
        using (var writer = new Utf8JsonWriter(buffer))
        {
            writer.WriteStartArray();
            foreach (string key in store.SortedKeys())
            {
                writer.WriteStringValue(key);
            }
            writer.WriteEndArray();
        }
        return WriteAsync(context, StatusCodes.Status200OK, buffer.WrittenMemory, "application/json");
    }

    private static Task WriteAsync(HttpContext context, int status, ReadOnlyMemory<byte> body, string contentType)
    {
        HttpResponse response = context.Response;
        response.StatusCode = status;
        response.ContentType = contentType;
        response.ContentLength = body.Length;
        return response.Body.WriteAsync(body, context.RequestAborted).AsTask();
    }

    private static Task Status(HttpContext context, int status)
    {
        HttpResponse response = context.Response;
        response.StatusCode = status;
        if (status != StatusCodes.Status204NoContent)
        {
            response.ContentLength = 0;
        }
        return Task.CompletedTask;
    }
}
