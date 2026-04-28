using Xunit;
using WebApp.Models;
using FluentAssertions;

namespace WebAppTests.Models;

public class DeviceTests
{
    [Fact]
    public void IsHealthy_WhenLastTelemetryWithinFiveMinutes_ReturnsTrue()
    {
        var device = new Device
        {
            Id = "1",
            AssetId = "rpi-001",
            Hostname = "raspberrypi",
            RegisteredAt = DateTime.UtcNow.AddDays(-1),
            LastTelemetryAt = DateTime.UtcNow.AddMinutes(-2)
        };

        device.IsHealthy.Should().BeTrue();
    }

    [Fact]
    public void IsHealthy_WhenLastTelemetryOlderThanFiveMinutes_ReturnsFalse()
    {
        var device = new Device
        {
            Id = "1",
            AssetId = "rpi-001",
            Hostname = "raspberrypi",
            RegisteredAt = DateTime.UtcNow.AddDays(-1),
            LastTelemetryAt = DateTime.UtcNow.AddMinutes(-10)
        };

        device.IsHealthy.Should().BeFalse();
    }

    [Fact]
    public void IsHealthy_WhenLastTelemetryIsNull_ReturnsFalse()
    {
        var device = new Device
        {
            Id = "1",
            AssetId = "rpi-001",
            Hostname = "raspberrypi",
            RegisteredAt = DateTime.UtcNow.AddDays(-1),
            LastTelemetryAt = null
        };

        device.IsHealthy.Should().BeFalse();
    }

    [Fact]
    public void IsHealthy_WhenLastTelemetryExactlyFiveMinutesAgo_ReturnsFalse()
    {
        // Adding an extra second ensures TotalMinutes > 5 deterministically
        var device = new Device
        {
            Id = "1",
            AssetId = "rpi-001",
            Hostname = "raspberrypi",
            RegisteredAt = DateTime.UtcNow.AddDays(-1),
            LastTelemetryAt = DateTime.UtcNow.AddMinutes(-5).AddSeconds(-1)
        };

        device.IsHealthy.Should().BeFalse();
    }

    [Fact]
    public void Device_CanBeCreatedWithAllRequiredProperties()
    {
        var registeredAt = DateTime.UtcNow.AddDays(-7);
        var lastTelemetry = DateTime.UtcNow.AddMinutes(-1);

        var device = new Device
        {
            Id = "abc123",
            AssetId = "rpi-42",
            Hostname = "edge-node-42",
            RegisteredAt = registeredAt,
            LastTelemetryAt = lastTelemetry
        };

        device.Id.Should().Be("abc123");
        device.AssetId.Should().Be("rpi-42");
        device.Hostname.Should().Be("edge-node-42");
        device.RegisteredAt.Should().Be(registeredAt);
        device.LastTelemetryAt.Should().Be(lastTelemetry);
    }
}
