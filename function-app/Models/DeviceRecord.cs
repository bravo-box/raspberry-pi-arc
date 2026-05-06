using Newtonsoft.Json;

namespace FleetFunctionApp.Models;

/// <summary>
/// Cosmos DB document stored in the <c>devices</c> container.
/// One document per registered Pi device, keyed by hostname.
/// </summary>
public sealed class DeviceRecord
{
    [JsonProperty("id")]
    public string Id { get; set; } = string.Empty;

    [JsonProperty("hostname")]
    public string Hostname { get; set; } = string.Empty;

    [JsonProperty("firstSeen")]
    public DateTimeOffset FirstSeen { get; set; }

    [JsonProperty("lastSeen")]
    public DateTimeOffset LastSeen { get; set; }

    [JsonProperty("imageCount")]
    public int ImageCount { get; set; }

    /// <summary>
    /// Unique device GUID assigned by the cloud during first-time registration.
    /// Empty string for devices registered via the legacy photo-upload path.
    /// </summary>
    [JsonProperty("deviceId")]
    public string DeviceId { get; set; } = string.Empty;
}
