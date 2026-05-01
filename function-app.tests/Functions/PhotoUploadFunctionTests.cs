using Azure.Messaging.ServiceBus;
using FleetFunctionApp.Functions;
using FleetFunctionApp.Models;
using FleetFunctionApp.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using System.Text.Json;
using Xunit;

namespace FleetFunctionApp.Tests.Functions;

public sealed class PhotoUploadFunctionTests
{
    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private static string Serialize(object obj) => JsonSerializer.Serialize(obj);

    private static (Mock<IFleetRepository> repo,
                    Mock<ServiceBusClient>  sbClient,
                    Mock<ServiceBusSender>  sender,
                    PhotoUploadFunction     sut)
        BuildSut()
    {
        var repo     = new Mock<IFleetRepository>();
        var sbClient = new Mock<ServiceBusClient>();
        var sender   = new Mock<ServiceBusSender>();

        sbClient.Setup(c => c.CreateSender("photo-processed"))
                .Returns(sender.Object);

        var sut = new PhotoUploadFunction(
            repo.Object,
            sbClient.Object,
            NullLogger<PhotoUploadFunction>.Instance);

        return (repo, sbClient, sender, sut);
    }

    private static FunctionContext MockContext() => new Mock<FunctionContext>().Object;

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------

    [Fact]
    public async Task RunAsync_ValidMessage_SavesImageUpsertDeviceAndSendsAck()
    {
        var (repo, _, sender, sut) = BuildSut();

        var message = new PhotoUploadMessage
        {
            FileName       = "pi1_20240101T120000_000000.jpg",
            HostName       = "pi1",
            StorageAccount = "testaccount",
            Container      = "photos"
        };

        await sut.RunAsync(Serialize(message), MockContext());

        // Image record persisted
        repo.Verify(r => r.SaveImageAsync(
            It.Is<ImageRecord>(img =>
                img.FileName == message.FileName &&
                img.HostName == message.HostName &&
                img.Container == message.Container),
            default), Times.Once);

        // Device record upserted
        repo.Verify(r => r.UpsertDeviceAsync(message.HostName, default), Times.Once);

        // Acknowledgement sent to Service Bus
        sender.Verify(s => s.SendMessageAsync(
            It.IsAny<ServiceBusMessage>(),
            default), Times.Once);
    }

    [Fact]
    public async Task RunAsync_InvalidJson_LogsErrorAndDoesNotThrow()
    {
        var (repo, _, sender, sut) = BuildSut();

        // Should not throw; function swallows poison messages.
        await sut.RunAsync("{ this is not valid json }", MockContext());

        repo.Verify(r => r.SaveImageAsync(It.IsAny<ImageRecord>(), default), Times.Never);
        repo.Verify(r => r.UpsertDeviceAsync(It.IsAny<string>(), default), Times.Never);
        sender.Verify(s => s.SendMessageAsync(It.IsAny<ServiceBusMessage>(), default), Times.Never);
    }

    [Fact]
    public async Task RunAsync_NullDeserializationResult_LogsWarningAndSkips()
    {
        var (repo, _, sender, sut) = BuildSut();

        // "null" is valid JSON but deserialises to null for a reference type.
        await sut.RunAsync("null", MockContext());

        repo.Verify(r => r.SaveImageAsync(It.IsAny<ImageRecord>(), default), Times.Never);
        repo.Verify(r => r.UpsertDeviceAsync(It.IsAny<string>(), default), Times.Never);
        sender.Verify(s => s.SendMessageAsync(It.IsAny<ServiceBusMessage>(), default), Times.Never);
    }

    [Fact]
    public async Task RunAsync_EmptyFileName_LogsWarningAndSkips()
    {
        var (repo, _, sender, sut) = BuildSut();

        var message = new PhotoUploadMessage
        {
            FileName  = "",       // missing required field
            HostName  = "pi1",
            Container = "photos"
        };

        await sut.RunAsync(Serialize(message), MockContext());

        repo.Verify(r => r.SaveImageAsync(It.IsAny<ImageRecord>(), default), Times.Never);
        repo.Verify(r => r.UpsertDeviceAsync(It.IsAny<string>(), default), Times.Never);
        sender.Verify(s => s.SendMessageAsync(It.IsAny<ServiceBusMessage>(), default), Times.Never);
    }

    [Fact]
    public async Task RunAsync_ValidMessage_ImageRecordHasCorrectFields()
    {
        var (repo, _, _, sut) = BuildSut();

        var message = new PhotoUploadMessage
        {
            FileName       = "pi2_20240601T080000_000001.jpg",
            HostName       = "pi2",
            StorageAccount = "myaccount",
            Container      = "photos"
        };

        ImageRecord? captured = null;
        repo.Setup(r => r.SaveImageAsync(It.IsAny<ImageRecord>(), default))
            .Callback<ImageRecord, CancellationToken>((img, _) => captured = img)
            .Returns(Task.CompletedTask);

        await sut.RunAsync(Serialize(message), MockContext());

        Assert.NotNull(captured);
        Assert.Equal(message.FileName,       captured!.Id);
        Assert.Equal(message.FileName,       captured.FileName);
        Assert.Equal(message.HostName,       captured.HostName);
        Assert.Equal(message.StorageAccount, captured.StorageAccount);
        Assert.Equal(message.Container,      captured.Container);
    }

    [Fact]
    public async Task RunAsync_ValidMessage_AckPayloadContainsFileName()
    {
        var (_, _, sender, sut) = BuildSut();

        var message = new PhotoUploadMessage
        {
            FileName = "pi1_20240101T120000_000000.jpg",
            HostName = "pi1"
        };

        ServiceBusMessage? sentMessage = null;
        sender.Setup(s => s.SendMessageAsync(It.IsAny<ServiceBusMessage>(), default))
              .Callback<ServiceBusMessage, CancellationToken>((m, _) => sentMessage = m)
              .Returns(Task.CompletedTask);

        await sut.RunAsync(Serialize(message), MockContext());

        Assert.NotNull(sentMessage);
        var body = sentMessage!.Body.ToString();
        Assert.Contains(message.FileName, body);
    }
}
