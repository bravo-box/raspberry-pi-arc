using System.Text.Json.Serialization;

namespace FleetFunctionApp.Models;

/// <summary>
/// Message published to the <c>device-registered</c> Service Bus topic by the
/// cloud function in response to a <see cref="RegisterDeviceMessage"/>.
/// </summary>
public sealed class DeviceRegisteredMessage
{
    [JsonPropertyName("hostname")]
    public string Hostname { get; set; } = string.Empty;

    [JsonPropertyName("device_id")]
    public string DeviceId { get; set; } = string.Empty;
}
