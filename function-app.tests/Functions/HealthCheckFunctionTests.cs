using FleetFunctionApp.Functions;
using FleetFunctionApp.Models;
using FleetFunctionApp.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using System.Text.Json;
using Xunit;

namespace FleetFunctionApp.Tests.Functions;

public sealed class HealthCheckFunctionTests
{
    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private static string Serialize(object obj) => JsonSerializer.Serialize(obj);

    private static (Mock<IFleetRepository> repo, HealthCheckFunction sut) BuildSut()
    {
        var repo = new Mock<IFleetRepository>();
        var sut  = new HealthCheckFunction(
            repo.Object,
            NullLogger<HealthCheckFunction>.Instance);
        return (repo, sut);
    }

    private static FunctionContext MockContext() => new Mock<FunctionContext>().Object;

    private static HealthCheckMessage ValidMessage() => new HealthCheckMessage
    {
        DeviceId        = "abc-device-guid-1234",
        Hostname        = "pi-device-1",
        NetworkStatus   = "connected",
        DiskTotalGb     = 32.0,
        DiskUsedGb      = 10.0,
        DiskFreeGb      = 22.0,
        DiskFreePercent = 68.75,
        Status          = "Green",
        Timestamp       = DateTimeOffset.UtcNow
    };

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------

    [Fact]
    public async Task RunAsync_ValidMessage_SavesHealthCheckRecord()
    {
        var (repo, sut) = BuildSut();

        await sut.RunAsync(Serialize(ValidMessage()), MockContext());

        repo.Verify(r => r.SaveHealthCheckAsync(
            It.Is<HealthCheckRecord>(rec =>
                rec.DeviceId       == "abc-device-guid-1234" &&
                rec.Hostname       == "pi-device-1"          &&
                rec.NetworkStatus  == "connected"             &&
                rec.Status         == "Green"),
            default), Times.Once);
    }

    [Fact]
    public async Task RunAsync_ValidMessage_RecordIdCombinesDeviceIdAndTimestamp()
    {
        var (repo, sut) = BuildSut();
        var msg = ValidMessage();

        HealthCheckRecord? captured = null;
        repo.Setup(r => r.SaveHealthCheckAsync(It.IsAny<HealthCheckRecord>(), default))
            .Callback<HealthCheckRecord, CancellationToken>((rec, _) => captured = rec)
            .Returns(Task.CompletedTask);

        await sut.RunAsync(Serialize(msg), MockContext());

        Assert.NotNull(captured);
        Assert.StartsWith(msg.DeviceId, captured!.Id);
    }

    [Fact]
    public async Task RunAsync_ValidMessage_RecordHasReceivedAtPopulated()
    {
        var (repo, sut) = BuildSut();
        var before = DateTimeOffset.UtcNow;

        HealthCheckRecord? captured = null;
        repo.Setup(r => r.SaveHealthCheckAsync(It.IsAny<HealthCheckRecord>(), default))
            .Callback<HealthCheckRecord, CancellationToken>((rec, _) => captured = rec)
            .Returns(Task.CompletedTask);

        await sut.RunAsync(Serialize(ValidMessage()), MockContext());

        var after = DateTimeOffset.UtcNow;
        Assert.NotNull(captured);
        Assert.True(captured!.ReceivedAt >= before && captured.ReceivedAt <= after,
            "ReceivedAt should be set to approximately now.");
    }

    [Fact]
    public async Task RunAsync_InvalidJson_DoesNotThrow()
    {
        var (repo, sut) = BuildSut();

        await sut.RunAsync("{ not valid json }", MockContext());

        repo.Verify(r => r.SaveHealthCheckAsync(It.IsAny<HealthCheckRecord>(), default), Times.Never);
    }

    [Fact]
    public async Task RunAsync_NullDeserialization_SkipsProcessing()
    {
        var (repo, sut) = BuildSut();

        await sut.RunAsync("null", MockContext());

        repo.Verify(r => r.SaveHealthCheckAsync(It.IsAny<HealthCheckRecord>(), default), Times.Never);
    }

    [Fact]
    public async Task RunAsync_MissingDeviceId_SkipsProcessing()
    {
        var (repo, sut) = BuildSut();

        var msg = ValidMessage();
        msg.DeviceId = "";

        await sut.RunAsync(Serialize(msg), MockContext());

        repo.Verify(r => r.SaveHealthCheckAsync(It.IsAny<HealthCheckRecord>(), default), Times.Never);
    }

    [Theory]
    [InlineData("Green",  "connected", 68.75)]
    [InlineData("Yellow", "connected", 40.0)]
    [InlineData("Yellow", "degraded",  60.0)]
    [InlineData("Red",    "disabled",  60.0)]
    [InlineData("Red",    "connected", 20.0)]
    public async Task RunAsync_VariousStatuses_RecordPreservesStatus(
        string status, string networkStatus, double diskFreePercent)
    {
        var (repo, sut) = BuildSut();

        var msg = ValidMessage();
        msg.Status          = status;
        msg.NetworkStatus   = networkStatus;
        msg.DiskFreePercent = diskFreePercent;

        HealthCheckRecord? captured = null;
        repo.Setup(r => r.SaveHealthCheckAsync(It.IsAny<HealthCheckRecord>(), default))
            .Callback<HealthCheckRecord, CancellationToken>((rec, _) => captured = rec)
            .Returns(Task.CompletedTask);

        await sut.RunAsync(Serialize(msg), MockContext());

        Assert.NotNull(captured);
        Assert.Equal(status,        captured!.Status);
        Assert.Equal(networkStatus, captured.NetworkStatus);
    }
}
