using System.Text.Json;
using Microsoft.AspNetCore.Http.Features;

namespace KvHttp;

/// <summary>Dispatches every request to the kvhttp routes.</summary>
public sealed class KvRequestHandler(KeyValueStore store)
{
    public const int MaxValueBytes = 1024 * 1024;

    private const string KvPrefix = "/kv/";

    private static ReadOnlySpan<byte> HealthBody => "ok"u8;

    public Task HandleAsync(HttpContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        // Use the raw target so percent-encoded characters are validated as written.
        string path = context.Features.Get<IHttpRequestFeature>()?.RawTarget ?? context.Request.Path.Value ?? "/";
        int query = path.IndexOf('?', StringComparison.Ordinal);
        if (query >= 0)
        {
            path = path[..query];
        }

        string method = context.Request.Method;

        if (path == "/health")
        {
            return HttpMethods.IsGet(method)
                ? WriteAsync(context.Response, StatusCodes.Status200OK, HealthBody.ToArray(), "text/plain")
                : MethodNotAllowed(context.Response, "GET");
        }

        if (path == "/kv")
        {
            return HttpMethods.IsGet(method)
                ? ListAsync(context.Response)
                : MethodNotAllowed(context.Response, "GET");
        }

        if (path.StartsWith(KvPrefix, StringComparison.Ordinal))
        {
            string key = path[KvPrefix.Length..];
            if (!KeyValidator.IsValid(key))
            {
                return Empty(context.Response, StatusCodes.Status400BadRequest);
            }

            if (HttpMethods.IsGet(method))
            {
                return store.TryGet(key, out byte[] value)
                    ? WriteAsync(context.Response, StatusCodes.Status200OK, value, "application/octet-stream")
                    : Empty(context.Response, StatusCodes.Status404NotFound);
            }

            if (HttpMethods.IsPut(method))
            {
                return PutAsync(context, key);
            }

            if (HttpMethods.IsDelete(method))
            {
                return Empty(context.Response, store.Remove(key) ? StatusCodes.Status204NoContent : StatusCodes.Status404NotFound);
            }

            return MethodNotAllowed(context.Response, "GET, PUT, DELETE");
        }

        return Empty(context.Response, StatusCodes.Status404NotFound);
    }

    private async Task PutAsync(HttpContext context, string key)
    {
        HttpRequest request = context.Request;
        if (request.ContentLength > MaxValueBytes)
        {
            await Empty(context.Response, StatusCodes.Status413PayloadTooLarge).ConfigureAwait(false);
            return;
        }

        byte[]? value = await ReadBodyAsync(request, context.RequestAborted).ConfigureAwait(false);
        if (value is null)
        {
            await Empty(context.Response, StatusCodes.Status413PayloadTooLarge).ConfigureAwait(false);
            return;
        }

        bool created = store.Put(key, value);
        await Empty(context.Response, created ? StatusCodes.Status201Created : StatusCodes.Status200OK).ConfigureAwait(false);
    }

    /// <summary>Reads the whole request body, or returns <see langword="null"/> if it exceeds the value limit.</summary>
    private static async Task<byte[]?> ReadBodyAsync(HttpRequest request, CancellationToken cancellationToken)
    {
        if (request.ContentLength is long length)
        {
            byte[] buffer = new byte[length];
            await request.Body.ReadExactlyAsync(buffer, cancellationToken).ConfigureAwait(false);
            return buffer;
        }

        using var stream = new MemoryStream();
        byte[] chunk = new byte[81920];
        int read;
        while ((read = await request.Body.ReadAsync(chunk, cancellationToken).ConfigureAwait(false)) > 0)
        {
            if (stream.Length + read > MaxValueBytes)
            {
                return null;
            }

            stream.Write(chunk, 0, read);
        }

        return stream.ToArray();
    }

    private Task ListAsync(HttpResponse response)
    {
        byte[] body = JsonSerializer.SerializeToUtf8Bytes(store.SortedKeys(), KvJsonContext.Default.StringArray);
        return WriteAsync(response, StatusCodes.Status200OK, body, "application/json");
    }

    private static Task MethodNotAllowed(HttpResponse response, string allow)
    {
        response.Headers.Allow = allow;
        return Empty(response, StatusCodes.Status405MethodNotAllowed);
    }

    private static Task Empty(HttpResponse response, int status)
    {
        response.StatusCode = status;
        if (status != StatusCodes.Status204NoContent)
        {
            response.ContentLength = 0;
        }

        return Task.CompletedTask;
    }

    private static Task WriteAsync(HttpResponse response, int status, byte[] body, string contentType)
    {
        response.StatusCode = status;
        response.ContentType = contentType;
        response.ContentLength = body.Length;
        return response.Body.WriteAsync(body).AsTask();
    }
}
