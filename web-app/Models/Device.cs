namespace FleetWebApp.Models;

/// <summary>Represents a registered Raspberry Pi device in the fleet.</summary>
public sealed class Device
{
    public string Id { get; set; } = string.Empty;
    public string Hostname { get; set; } = string.Empty;
    public DateTimeOffset FirstSeen { get; set; }
    public DateTimeOffset LastSeen { get; set; }
    public int ImageCount { get; set; }
}
