using Newtonsoft.Json;

namespace WebApp.Models;

public class ImageRecord
{
    [JsonProperty("id")]
    public string Id { get; set; } = string.Empty;

    [JsonProperty("assetId")]
    public string AssetId { get; set; } = string.Empty;

    [JsonProperty("blobUrl")]
    public string BlobUrl { get; set; } = string.Empty;

    [JsonProperty("capturedAt")]
    public DateTime CapturedAt { get; set; }
}
