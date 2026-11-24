using System.Text.Json;
using Microsoft.AspNetCore.Http.Features;

namespace KvHttp;

/// <summary>Terminal request handler implementing the kvhttp routes.</summary>
public sealed class KvHandler(KeyValueStore store)
{
    public const int MaxValueBytes = 1024 * 1024;

    private const string KvPrefix = "/kv/";
    private static readonly byte[] HealthBody = "ok"u8.ToArray();

    public Task HandleAsync(HttpContext context)
    {
        // Route on the raw request target so that Kestrel's path normalisation
        // (dot-segment removal, percent-decoding) cannot turn an invalid key into a valid route.
        var path = context.Features.Get<IHttpRequestFeature>()?.RawTarget ?? context.Request.Path.Value ?? "/";
        var queryStart = path.IndexOf('?');
        if (queryStart >= 0)
        {
            path = path[..queryStart];
        }

        var method = context.Request.Method;

        if (path == "/health")
        {
            return HttpMethods.IsGet(method) ? WriteBytesAsync(context, StatusCodes.Status200OK, HealthBody, "text/plain") : Status(context, StatusCodes.Status405MethodNotAllowed);
        }

        if (path == "/kv")
        {
            return HttpMethods.IsGet(method) ? ListAsync(context) : Status(context, StatusCodes.Status405MethodNotAllowed);
        }

        if (path.StartsWith(KvPrefix, StringComparison.Ordinal))
        {
            var isKnownMethod = HttpMethods.IsGet(method) || HttpMethods.IsPut(method) || HttpMethods.IsDelete(method);
            if (!isKnownMethod)
            {
                return Status(context, StatusCodes.Status405MethodNotAllowed);
            }

            var key = path[KvPrefix.Length..];
            if (!KeyValidator.IsValid(key))
            {
                return Status(context, StatusCodes.Status400BadRequest);
            }

            if (HttpMethods.IsGet(method))
            {
                return store.TryGet(key, out var value)
                    ? WriteBytesAsync(context, StatusCodes.Status200OK, value, "application/octet-stream")
                    : Status(context, StatusCodes.Status404NotFound);
            }

            if (HttpMethods.IsPut(method))
            {
                return PutAsync(context, key);
            }

            return Status(context, store.Delete(key) ? StatusCodes.Status204NoContent : StatusCodes.Status404NotFound);
        }

        return Status(context, StatusCodes.Status404NotFound);
    }

    private async Task PutAsync(HttpContext context, string key)
    {
        var declaredLength = context.Request.ContentLength;
        if (declaredLength > MaxValueBytes)
        {
            await Status(context, StatusCodes.Status413PayloadTooLarge);
            return;
        }

        var value = await ReadBodyAsync(context.Request, declaredLength, context.RequestAborted);
        if (value is null)
        {
            await Status(context, StatusCodes.Status413PayloadTooLarge);
            return;
        }

        var created = store.Put(key, value);
        await Status(context, created ? StatusCodes.Status201Created : StatusCodes.Status200OK);
    }

    /// <summary>Reads the whole request body, or returns <c>null</c> if it exceeds <see cref="MaxValueBytes"/>.</summary>
    private static async Task<byte[]?> ReadBodyAsync(HttpRequest request, long? declaredLength, CancellationToken cancellationToken)
    {
        if (declaredLength is { } length)
        {
            var buffer = new byte[length];
            await request.Body.ReadExactlyAsync(buffer, cancellationToken);
            return buffer;
        }

        using var stream = new MemoryStream();
        var chunk = new byte[16 * 1024];
        int read;
        while ((read = await request.Body.ReadAsync(chunk, cancellationToken)) > 0)
        {
            if (stream.Length + read > MaxValueBytes)
            {
                return null;
            }

            stream.Write(chunk, 0, read);
        }

        return stream.ToArray();
    }

    private Task ListAsync(HttpContext context)
    {
        var body = JsonSerializer.SerializeToUtf8Bytes(store.SortedKeys(), KvJsonContext.Default.StringArray);
        return WriteBytesAsync(context, StatusCodes.Status200OK, body, "application/json");
    }

    private static Task WriteBytesAsync(HttpContext context, int statusCode, byte[] body, string contentType)
    {
        var response = context.Response;
        response.StatusCode = statusCode;
        response.ContentType = contentType;
        response.ContentLength = body.Length;
        return response.Body.WriteAsync(body, context.RequestAborted).AsTask();
    }

    private static Task Status(HttpContext context, int statusCode)
    {
        var response = context.Response;
        response.StatusCode = statusCode;
        if (statusCode != StatusCodes.Status204NoContent)
        {
            response.ContentLength = 0;
        }

        return Task.CompletedTask;
    }
}
