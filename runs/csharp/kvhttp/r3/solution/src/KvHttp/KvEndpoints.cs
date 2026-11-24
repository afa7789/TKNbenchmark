using System.Buffers;
using System.Text.Json;
using Microsoft.AspNetCore.Http.Features;

namespace KvHttp;

/// <summary>Request dispatch for the kvhttp protocol.</summary>
public static class KvEndpoints
{
    public const int MaxValueBytes = 1024 * 1024;
    private const int MaxKeyLength = 64;
    private const string KvPrefix = "/kv/";

    private static readonly byte[] OkBody = "ok"u8.ToArray();

    public static async Task HandleAsync(HttpContext context, KvStore store)
    {
        var request = context.Request;
        var response = context.Response;
        string path = RawPath(context);
        string method = request.Method;

        if (path == "/health")
        {
            if (!HttpMethods.IsGet(method))
            {
                await WriteStatus(response, StatusCodes.Status405MethodNotAllowed, "GET");
                return;
            }
            await WriteBody(response, StatusCodes.Status200OK, OkBody, "text/plain; charset=utf-8");
            return;
        }

        if (path == "/kv")
        {
            if (!HttpMethods.IsGet(method))
            {
                await WriteStatus(response, StatusCodes.Status405MethodNotAllowed, "GET");
                return;
            }
            byte[] json = JsonSerializer.SerializeToUtf8Bytes(store.SortedKeys(), KvJsonContext.Default.StringArray);
            await WriteBody(response, StatusCodes.Status200OK, json, "application/json");
            return;
        }

        if (!path.StartsWith(KvPrefix, StringComparison.Ordinal))
        {
            await WriteStatus(response, StatusCodes.Status404NotFound);
            return;
        }

        bool isGet = HttpMethods.IsGet(method);
        bool isPut = HttpMethods.IsPut(method);
        bool isDelete = HttpMethods.IsDelete(method);
        if (!isGet && !isPut && !isDelete)
        {
            await WriteStatus(response, StatusCodes.Status405MethodNotAllowed, "GET, PUT, DELETE");
            return;
        }

        string key = path[KvPrefix.Length..];
        if (!IsValidKey(key))
        {
            await WriteStatus(response, StatusCodes.Status400BadRequest);
            return;
        }

        if (isGet)
        {
            if (store.TryGet(key, out byte[] value))
            {
                await WriteBody(response, StatusCodes.Status200OK, value, "application/octet-stream");
            }
            else
            {
                await WriteStatus(response, StatusCodes.Status404NotFound);
            }
        }
        else if (isPut)
        {
            byte[]? body = await ReadBodyAsync(request, context.RequestAborted);
            if (body is null)
            {
                await WriteStatus(response, StatusCodes.Status413PayloadTooLarge);
                return;
            }
            bool created = store.Put(key, body);
            await WriteStatus(response, created ? StatusCodes.Status201Created : StatusCodes.Status200OK);
        }
        else
        {
            await WriteStatus(response, store.Delete(key) ? StatusCodes.Status204NoContent : StatusCodes.Status404NotFound);
        }
    }

    public static bool IsValidKey(ReadOnlySpan<char> key)
    {
        if (key.Length is 0 or > MaxKeyLength)
        {
            return false;
        }
        foreach (char c in key)
        {
            if (!(char.IsAsciiLetterOrDigit(c) || c == '_' || c == '-'))
            {
                return false;
            }
        }
        return true;
    }

    /// <summary>
    /// Uses the undecoded request target so that percent-encoded characters
    /// (e.g. <c>%2F</c>) are treated as invalid key characters rather than decoded.
    /// </summary>
    private static string RawPath(HttpContext context)
    {
        string? raw = context.Features.Get<IHttpRequestFeature>()?.RawTarget;
        if (string.IsNullOrEmpty(raw) || raw[0] != '/')
        {
            return context.Request.Path.Value ?? "/";
        }
        int query = raw.IndexOf('?');
        return query >= 0 ? raw[..query] : raw;
    }

    /// <returns>The request body, or <c>null</c> if it exceeds <see cref="MaxValueBytes"/>.</returns>
    private static async Task<byte[]?> ReadBodyAsync(HttpRequest request, CancellationToken cancellationToken)
    {
        long? declared = request.ContentLength;
        if (declared > MaxValueBytes)
        {
            return null;
        }

        if (declared is long length)
        {
            byte[] exact = new byte[length];
            await request.Body.ReadExactlyAsync(exact, cancellationToken);
            return exact;
        }

        // No Content-Length (e.g. chunked): read up to the limit.
        var buffer = new ArrayBufferWriter<byte>();
        while (true)
        {
            Memory<byte> chunk = buffer.GetMemory(16 * 1024);
            int read = await request.Body.ReadAsync(chunk, cancellationToken);
            if (read == 0)
            {
                return buffer.WrittenSpan.ToArray();
            }
            buffer.Advance(read);
            if (buffer.WrittenCount > MaxValueBytes)
            {
                return null;
            }
        }
    }

    private static Task WriteStatus(HttpResponse response, int status, string? allow = null)
    {
        response.StatusCode = status;
        if (allow is not null)
        {
            response.Headers.Allow = allow;
        }
        if (status != StatusCodes.Status204NoContent)
        {
            response.ContentLength = 0;
        }
        return Task.CompletedTask;
    }

    private static Task WriteBody(HttpResponse response, int status, byte[] body, string contentType)
    {
        response.StatusCode = status;
        response.ContentType = contentType;
        response.ContentLength = body.Length;
        return response.Body.WriteAsync(body).AsTask();
    }
}
