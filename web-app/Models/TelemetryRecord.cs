using Newtonsoft.Json;

namespace WebApp.Models;

public class TelemetryRecord
{
    [JsonProperty("id")]
    public string Id { get; set; } = string.Empty;

    [JsonProperty("assetId")]
    public string AssetId { get; set; } = string.Empty;

    [JsonProperty("temperature")]
    public double Temperature { get; set; }

    [JsonProperty("unit")]
    public string Unit { get; set; } = "C";

    [JsonProperty("timestamp")]
    public DateTime Timestamp { get; set; }
}
