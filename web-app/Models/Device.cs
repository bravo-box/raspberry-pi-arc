using Newtonsoft.Json;

namespace WebApp.Models;

public class Device
{
    [JsonProperty("id")]
    public string Id { get; set; } = string.Empty;

    [JsonProperty("assetId")]
    public string AssetId { get; set; } = string.Empty;

    [JsonProperty("hostname")]
    public string Hostname { get; set; } = string.Empty;

    [JsonProperty("registeredAt")]
    public DateTime RegisteredAt { get; set; }

    [JsonProperty("lastTelemetryAt")]
    public DateTime? LastTelemetryAt { get; set; }

    public bool IsHealthy => LastTelemetryAt.HasValue
        && (DateTime.UtcNow - LastTelemetryAt.Value).TotalMinutes <= 5;
}
