using System.Text.Json.Serialization;

namespace FleetFunctionApp.Models;

/// <summary>
/// Health-check heartbeat published to the <c>health-check</c> Service Bus
/// topic every 30 seconds by the Pi's registration-service.
/// </summary>
public sealed class HealthCheckMessage
{
    [JsonPropertyName("device_id")]
    public string DeviceId { get; set; } = string.Empty;

    [JsonPropertyName("hostname")]
    public string Hostname { get; set; } = string.Empty;

    /// <summary>One of "connected", "degraded", or "disabled".</summary>
    [JsonPropertyName("network_status")]
    public string NetworkStatus { get; set; } = string.Empty;

    [JsonPropertyName("disk_total_gb")]
    public double DiskTotalGb { get; set; }

    [JsonPropertyName("disk_used_gb")]
    public double DiskUsedGb { get; set; }

    [JsonPropertyName("disk_free_gb")]
    public double DiskFreeGb { get; set; }

    [JsonPropertyName("disk_free_percent")]
    public double DiskFreePercent { get; set; }

    /// <summary>One of "Green", "Yellow", or "Red".</summary>
    [JsonPropertyName("status")]
    public string Status { get; set; } = string.Empty;

    [JsonPropertyName("timestamp")]
    public DateTimeOffset Timestamp { get; set; }
}
