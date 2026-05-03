using Newtonsoft.Json;

namespace FleetFunctionApp.Models;

/// <summary>
/// Cosmos DB document stored in the <c>health-checks</c> container.
/// One document per health-check heartbeat received from a Pi device.
/// </summary>
public sealed class HealthCheckRecord
{
    /// <summary>Unique document ID — combines device ID and timestamp.</summary>
    [JsonProperty("id")]
    public string Id { get; set; } = string.Empty;

    /// <summary>Partition key — device GUID assigned at registration.</summary>
    [JsonProperty("deviceId")]
    public string DeviceId { get; set; } = string.Empty;

    [JsonProperty("hostname")]
    public string Hostname { get; set; } = string.Empty;

    /// <summary>One of "connected", "degraded", or "disabled".</summary>
    [JsonProperty("networkStatus")]
    public string NetworkStatus { get; set; } = string.Empty;

    [JsonProperty("diskTotalGb")]
    public double DiskTotalGb { get; set; }

    [JsonProperty("diskUsedGb")]
    public double DiskUsedGb { get; set; }

    [JsonProperty("diskFreeGb")]
    public double DiskFreeGb { get; set; }

    [JsonProperty("diskFreePercent")]
    public double DiskFreePercent { get; set; }

    /// <summary>One of "Green", "Yellow", or "Red".</summary>
    [JsonProperty("status")]
    public string Status { get; set; } = string.Empty;

    [JsonProperty("timestamp")]
    public DateTimeOffset Timestamp { get; set; }

    [JsonProperty("receivedAt")]
    public DateTimeOffset ReceivedAt { get; set; }
}
