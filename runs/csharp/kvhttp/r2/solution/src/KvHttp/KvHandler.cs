using System.Buffers;
using System.IO.Pipelines;
using System.Text.Json;
using Microsoft.AspNetCore.Http.Features;

namespace KvHttp;

/// <summary>
/// Routes requests by hand against the raw request target so that encoded or
/// dot-segment paths are validated exactly as sent rather than after normalization.
/// </summary>
public sealed class KvHandler(KeyValueStore store)
{
    public const int MaxValueBytes = 1024 * 1024;
    private const string KvPrefix = "/kv/";

    private static ReadOnlySpan<byte> HealthBody => "ok"u8;

    public Task HandleAsync(HttpContext context)
    {
        string target = context.Features.Get<IHttpRequestFeature>()?.RawTarget ?? context.Request.Path.Value ?? "/";
        string path = StripQuery(target);
        string method = context.Request.Method;

        if (path == "/health")
        {
            return HttpMethods.IsGet(method) ? WriteBytesAsync(context, StatusCodes.Status200OK, HealthBody, "text/plain") : MethodNotAllowed(context, "GET");
        }

        if (path == "/kv")
        {
            return HttpMethods.IsGet(method) ? ListAsync(context) : MethodNotAllowed(context, "GET");
        }

        if (path.StartsWith(KvPrefix, StringComparison.Ordinal))
        {
            string key = path[KvPrefix.Length..];
            if (!IsValidKey(key))
            {
                return Status(context, StatusCodes.Status400BadRequest);
            }

            bool knownMethod = HttpMethods.IsGet(method) || HttpMethods.IsPut(method) || HttpMethods.IsDelete(method);
            if (!knownMethod)
            {
                return MethodNotAllowed(context, "GET, PUT, DELETE");
            }

            if (HttpMethods.IsGet(method))
            {
                return GetAsync(context, key);
            }

            if (HttpMethods.IsPut(method))
            {
                return PutAsync(context, key);
            }

            return Status(context, store.Delete(key) ? StatusCodes.Status204NoContent : StatusCodes.Status404NotFound);
        }

        return Status(context, StatusCodes.Status404NotFound);
    }

    public static bool IsValidKey(ReadOnlySpan<char> key)
    {
        if (key.Length is < 1 or > 64)
        {
            return false;
        }

        foreach (char c in key)
        {
            if (!(char.IsAsciiLetterOrDigit(c) || c is '_' or '-'))
            {
                return false;
            }
        }

        return true;
    }

    private static string StripQuery(string target)
    {
        int q = target.IndexOf('?');
        return q >= 0 ? target[..q] : target;
    }

    private Task GetAsync(HttpContext context, string key)
    {
        return store.TryGet(key, out byte[] value)
            ? WriteBytesAsync(context, StatusCodes.Status200OK, value, "application/octet-stream")
            : Status(context, StatusCodes.Status404NotFound);
    }

    private async Task PutAsync(HttpContext context, string key)
    {
        long? declared = context.Request.ContentLength;
        if (declared > MaxValueBytes)
        {
            await Status(context, StatusCodes.Status413PayloadTooLarge);
            return;
        }

        byte[]? value = await ReadBodyAsync(context.Request, context.RequestAborted);
        if (value is null)
        {
            await Status(context, StatusCodes.Status413PayloadTooLarge);
            return;
        }

        bool created = store.Put(key, value);
        await Status(context, created ? StatusCodes.Status201Created : StatusCodes.Status200OK);
    }

    /// <summary>Reads the full request body, or returns <c>null</c> if it exceeds <see cref="MaxValueBytes"/>.</summary>
    private static async Task<byte[]?> ReadBodyAsync(HttpRequest request, CancellationToken cancellationToken)
    {
        var reader = request.BodyReader;
        while (true)
        {
            ReadResult result = await reader.ReadAsync(cancellationToken);
            ReadOnlySequence<byte> buffer = result.Buffer;

            if (buffer.Length > MaxValueBytes)
            {
                reader.AdvanceTo(buffer.End);
                return null;
            }

            if (result.IsCompleted)
            {
                byte[] value = buffer.ToArray();
                reader.AdvanceTo(buffer.End);
                return value;
            }

            reader.AdvanceTo(buffer.Start, buffer.End);
        }
    }

    private Task ListAsync(HttpContext context)
    {
        byte[] json = JsonSerializer.SerializeToUtf8Bytes(store.SortedKeys(), KvJsonContext.Default.StringArray);
        return WriteBytesAsync(context, StatusCodes.Status200OK, json, "application/json");
    }

    private static Task MethodNotAllowed(HttpContext context, string allow)
    {
        context.Response.Headers.Allow = allow;
        return Status(context, StatusCodes.Status405MethodNotAllowed);
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

    private static Task WriteBytesAsync(HttpContext context, int statusCode, ReadOnlySpan<byte> body, string contentType)
    {
        var response = context.Response;
        response.StatusCode = statusCode;
        response.ContentType = contentType;
        response.ContentLength = body.Length;
        response.BodyWriter.Write(body);
        return response.BodyWriter.FlushAsync(context.RequestAborted).AsTask();
    }
}
