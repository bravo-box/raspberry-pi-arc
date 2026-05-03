using Azure.Messaging.ServiceBus;
using Azure.Storage.Blobs;
using FleetFunctionApp.Functions;
using FleetFunctionApp.Models;
using FleetFunctionApp.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using System.Text.Json;
using Xunit;

namespace FleetFunctionApp.Tests.Functions;

public sealed class RegisterDeviceFunctionTests
{
    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private static string Serialize(object obj) => JsonSerializer.Serialize(obj);

    private static (Mock<IFleetRepository>  repo,
                    Mock<ServiceBusClient>   sbClient,
                    Mock<ServiceBusSender>   sender,
                    Mock<BlobServiceClient>  blobClient,
                    RegisterDeviceFunction   sut)
        BuildSut(string? deviceId = "test-guid-1234")
    {
        var repo       = new Mock<IFleetRepository>();
        var sbClient   = new Mock<ServiceBusClient>();
        var sender     = new Mock<ServiceBusSender>();
        var blobClient = new Mock<BlobServiceClient>();

        sbClient.Setup(c => c.CreateSender("device-registered"))
                .Returns(sender.Object);

        repo.Setup(r => r.RegisterDeviceAsync(It.IsAny<string>(), default))
            .ReturnsAsync(deviceId ?? Guid.NewGuid().ToString());

        // Blob container mock – CreateIfNotExistsAsync returns null to simulate
        // the container already existing (non-null value = newly created).
        var containerClient = new Mock<BlobContainerClient>();
        containerClient.Setup(c => c.CreateIfNotExistsAsync(
                It.IsAny<Azure.Storage.Blobs.Models.PublicAccessType>(),
                It.IsAny<IDictionary<string, string>>(),
                It.IsAny<Azure.Storage.Blobs.Models.BlobContainerEncryptionScopeOptions>(),
                default))
            .ReturnsAsync((Azure.Response<Azure.Storage.Blobs.Models.BlobContainerInfo>?)null);

        blobClient.Setup(b => b.GetBlobContainerClient(It.IsAny<string>()))
                  .Returns(containerClient.Object);

        var sut = new RegisterDeviceFunction(
            repo.Object,
            sbClient.Object,
            blobClient.Object,
            NullLogger<RegisterDeviceFunction>.Instance);

        return (repo, sbClient, sender, blobClient, sut);
    }

    private static FunctionContext MockContext() => new Mock<FunctionContext>().Object;

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------

    [Fact]
    public async Task RunAsync_ValidMessage_RegistersDeviceAndSendsResponse()
    {
        var (repo, _, sender, _, sut) = BuildSut("abc-device-guid");

        var message = new RegisterDeviceMessage { Hostname = "pi-device-1" };
        await sut.RunAsync(Serialize(message), MockContext());

        // Device was registered
        repo.Verify(r => r.RegisterDeviceAsync("pi-device-1", default), Times.Once);

        // Response was sent
        sender.Verify(s => s.SendMessageAsync(
            It.IsAny<ServiceBusMessage>(), default), Times.Once);
    }

    [Fact]
    public async Task RunAsync_ValidMessage_ResponseContainsHostnameAndDeviceId()
    {
        var (_, _, sender, _, sut) = BuildSut("my-guid-5678");

        var message = new RegisterDeviceMessage { Hostname = "pi-device-2" };

        ServiceBusMessage? sentMessage = null;
        sender.Setup(s => s.SendMessageAsync(It.IsAny<ServiceBusMessage>(), default))
              .Callback<ServiceBusMessage, CancellationToken>((m, _) => sentMessage = m)
              .Returns(Task.CompletedTask);

        await sut.RunAsync(Serialize(message), MockContext());

        Assert.NotNull(sentMessage);
        var body = sentMessage!.Body.ToString();
        Assert.Contains("pi-device-2", body);
        Assert.Contains("my-guid-5678", body);
    }

    [Fact]
    public async Task RunAsync_InvalidJson_DoesNotThrow()
    {
        var (repo, _, sender, _, sut) = BuildSut();

        await sut.RunAsync("{ not valid json }", MockContext());

        repo.Verify(r => r.RegisterDeviceAsync(It.IsAny<string>(), default), Times.Never);
        sender.Verify(s => s.SendMessageAsync(It.IsAny<ServiceBusMessage>(), default), Times.Never);
    }

    [Fact]
    public async Task RunAsync_MissingHostname_SkipsProcessing()
    {
        var (repo, _, sender, _, sut) = BuildSut();

        var message = new RegisterDeviceMessage { Hostname = "" };
        await sut.RunAsync(Serialize(message), MockContext());

        repo.Verify(r => r.RegisterDeviceAsync(It.IsAny<string>(), default), Times.Never);
        sender.Verify(s => s.SendMessageAsync(It.IsAny<ServiceBusMessage>(), default), Times.Never);
    }

    [Fact]
    public async Task RunAsync_NullDeserialization_SkipsProcessing()
    {
        var (repo, _, sender, _, sut) = BuildSut();

        await sut.RunAsync("null", MockContext());

        repo.Verify(r => r.RegisterDeviceAsync(It.IsAny<string>(), default), Times.Never);
        sender.Verify(s => s.SendMessageAsync(It.IsAny<ServiceBusMessage>(), default), Times.Never);
    }

    // ------------------------------------------------------------------
    // NormaliseContainerName tests
    // ------------------------------------------------------------------

    [Theory]
    [InlineData("pi-device-1",     "pi-device-1")]
    [InlineData("PI_DEVICE_1",     "pi-device-1")]
    [InlineData("pi..device",      "pi-device")]
    [InlineData("--leading",       "leading")]
    [InlineData("trailing--",      "trailing")]
    [InlineData("a",               "a00")]  // padded to minimum 3 chars
    [InlineData("UPPERCASE_HOST",  "uppercase-host")]
    public void NormaliseContainerName_VariousInputs_ReturnsValidName(
        string input, string expected)
    {
        var result = RegisterDeviceFunction.NormaliseContainerName(input);
        Assert.Equal(expected, result);
        Assert.True(result.Length >= 3 && result.Length <= 63,
            $"Container name length {result.Length} is outside 3-63 range.");
        Assert.Matches(@"^[a-z0-9][a-z0-9\-]*[a-z0-9]$", result.Length >= 2 ? result : result + "x");
    }

    [Fact]
    public void NormaliseContainerName_LongHostname_TruncatesTo63Chars()
    {
        var longHostname = new string('a', 100);
        var result = RegisterDeviceFunction.NormaliseContainerName(longHostname);
        Assert.True(result.Length <= 63);
    }
}
