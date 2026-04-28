using Xunit;
using System.Text;
using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Moq;
using FluentAssertions;
using WebApp.Services;

namespace WebAppTests.Services;

public class ServiceBusServiceTests
{
    private const string TopicName = "device-commands";

    private static (ServiceBusService service, Mock<ServiceBusSender> mockSender) CreateService()
    {
        var mockSender = new Mock<ServiceBusSender>();
        var mockClient = new Mock<ServiceBusClient>();

        var configValues = new Dictionary<string, string?>
        {
            ["ServiceBus:CommandsTopic"] = TopicName
        };
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(configValues)
            .Build();

        mockClient.Setup(c => c.CreateSender(TopicName)).Returns(mockSender.Object);

        var service = new ServiceBusService(
            mockClient.Object,
            configuration,
            Mock.Of<ILogger<ServiceBusService>>());

        return (service, mockSender);
    }

    [Fact]
    public async Task SendTakePictureCommandAsync_SendsMessageWithCorrectFormat()
    {
        var (service, mockSender) = CreateService();
        const string assetId = "rpi-001";

        await service.SendTakePictureCommandAsync(assetId);

        mockSender.Verify(s => s.SendMessageAsync(
            It.Is<ServiceBusMessage>(m =>
                Encoding.UTF8.GetString(m.Body.ToArray()).Contains("\"command\":\"take-picture\"") &&
                Encoding.UTF8.GetString(m.Body.ToArray()).Contains($"\"assetId\":\"{assetId}\"")),
            It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public async Task SendTakePictureCommandAsync_MessageHasJsonContentType()
    {
        var (service, mockSender) = CreateService();

        await service.SendTakePictureCommandAsync("rpi-001");

        mockSender.Verify(s => s.SendMessageAsync(
            It.Is<ServiceBusMessage>(m => m.ContentType == "application/json"),
            It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public async Task SendTakePictureCommandAsync_UsesSenderCreatedForCorrectTopic()
    {
        var mockSender = new Mock<ServiceBusSender>();
        var mockClient = new Mock<ServiceBusClient>();

        var configValues = new Dictionary<string, string?>
        {
            ["ServiceBus:CommandsTopic"] = TopicName
        };
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(configValues)
            .Build();

        mockClient.Setup(c => c.CreateSender(TopicName)).Returns(mockSender.Object);

        _ = new ServiceBusService(
            mockClient.Object,
            configuration,
            Mock.Of<ILogger<ServiceBusService>>());

        mockClient.Verify(c => c.CreateSender(TopicName), Times.Once);
    }

    [Fact]
    public async Task SendTakePictureCommandAsync_WhenSenderThrows_ExceptionPropagates()
    {
        var (service, mockSender) = CreateService();
        mockSender
            .Setup(s => s.SendMessageAsync(It.IsAny<ServiceBusMessage>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new ServiceBusException("Service unavailable", ServiceBusFailureReason.ServiceBusy));

        Func<Task> act = async () => await service.SendTakePictureCommandAsync("rpi-001");

        await act.Should().ThrowAsync<ServiceBusException>();
    }
}
