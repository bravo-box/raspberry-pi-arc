using System.Text.Json.Serialization;

namespace FleetFunctionApp.Models;

/// <summary>
/// Message published to the <c>register-device</c> Service Bus topic by a Pi
/// device on first startup.
/// </summary>
public sealed class RegisterDeviceMessage
{
    [JsonPropertyName("hostname")]
    public string Hostname { get; set; } = string.Empty;
}
