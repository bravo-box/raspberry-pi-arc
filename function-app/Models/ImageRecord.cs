using Newtonsoft.Json;

namespace FleetFunctionApp.Models;

/// <summary>
/// Cosmos DB document stored in the <c>images</c> container.
/// One document per camera image uploaded from the Pi fleet.
/// </summary>
public sealed class ImageRecord
{
    /// <summary>Unique document ID — equals <see cref="FileName"/>.</summary>
    [JsonProperty("id")]
    public string Id { get; set; } = string.Empty;

    /// <summary>Partition key — hostname of the Pi that captured the image.</summary>
    [JsonProperty("hostName")]
    public string HostName { get; set; } = string.Empty;

    /// <summary>Blob file name (e.g. <c>hostname_20240101T120000_000000.jpg</c>).</summary>
    [JsonProperty("fileName")]
    public string FileName { get; set; } = string.Empty;

    /// <summary>Azure Storage account that holds the blob.</summary>
    [JsonProperty("storageAccount")]
    public string StorageAccount { get; set; } = string.Empty;

    /// <summary>Blob container name.</summary>
    [JsonProperty("container")]
    public string Container { get; set; } = string.Empty;

    /// <summary>UTC timestamp when the image was received by the cloud.</summary>
    [JsonProperty("uploadedAt")]
    public DateTimeOffset UploadedAt { get; set; }
}
