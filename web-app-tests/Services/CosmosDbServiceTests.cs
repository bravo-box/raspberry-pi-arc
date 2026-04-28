using Xunit;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Moq;
using FluentAssertions;
using WebApp.Models;
using WebApp.Services;

namespace WebAppTests.Services;

public class CosmosDbServiceTests
{
    private readonly Mock<CosmosClient> _mockCosmosClient;
    private readonly Mock<Database> _mockDatabase;
    private readonly Mock<Container> _mockFleetContainer;
    private readonly Mock<Container> _mockTelemetryContainer;
    private readonly Mock<Container> _mockImagesContainer;
    private readonly IConfiguration _configuration;
    private readonly ILogger<CosmosDbService> _logger;

    public CosmosDbServiceTests()
    {
        _mockCosmosClient = new Mock<CosmosClient>();
        _mockDatabase = new Mock<Database>();
        _mockFleetContainer = new Mock<Container>();
        _mockTelemetryContainer = new Mock<Container>();
        _mockImagesContainer = new Mock<Container>();

        var configValues = new Dictionary<string, string?>
        {
            ["CosmosDb:DatabaseName"] = "rpi-arc",
            ["CosmosDb:FleetContainer"] = "fleet",
            ["CosmosDb:TelemetryContainer"] = "telemetry",
            ["CosmosDb:ImagesContainer"] = "images"
        };
        _configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(configValues)
            .Build();

        _logger = Mock.Of<ILogger<CosmosDbService>>();

        _mockCosmosClient.Setup(c => c.GetDatabase("rpi-arc")).Returns(_mockDatabase.Object);
        _mockDatabase.Setup(d => d.GetContainer("fleet")).Returns(_mockFleetContainer.Object);
        _mockDatabase.Setup(d => d.GetContainer("telemetry")).Returns(_mockTelemetryContainer.Object);
        _mockDatabase.Setup(d => d.GetContainer("images")).Returns(_mockImagesContainer.Object);
    }

    private CosmosDbService CreateService() =>
        new CosmosDbService(_mockCosmosClient.Object, _configuration, _logger);

    private static Mock<FeedIterator<T>> CreateMockIterator<T>(IList<T> items)
    {
        var mockResponse = new Mock<FeedResponse<T>>();
        mockResponse.Setup(r => r.GetEnumerator()).Returns(items.GetEnumerator());

        var mockIterator = new Mock<FeedIterator<T>>();
        mockIterator.SetupSequence(i => i.HasMoreResults)
            .Returns(true)
            .Returns(false);
        mockIterator.Setup(i => i.ReadNextAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(mockResponse.Object);

        return mockIterator;
    }

    [Fact]
    public async Task GetAllDevicesAsync_ReturnsDeviceList()
    {
        var devices = new List<Device>
        {
            new Device { Id = "1", AssetId = "rpi-001", Hostname = "node-1" },
            new Device { Id = "2", AssetId = "rpi-002", Hostname = "node-2" }
        };
        var mockIterator = CreateMockIterator(devices);
        _mockFleetContainer
            .Setup(c => c.GetItemQueryIterator<Device>(
                It.IsAny<QueryDefinition>(),
                It.IsAny<string?>(),
                It.IsAny<QueryRequestOptions?>()))
            .Returns(mockIterator.Object);

        var service = CreateService();
        var result = await service.GetAllDevicesAsync();

        result.Should().HaveCount(2);
        result.Should().Contain(d => d.AssetId == "rpi-001");
        result.Should().Contain(d => d.AssetId == "rpi-002");
    }

    [Fact]
    public async Task GetDeviceAsync_WithValidAssetId_ReturnsDevice()
    {
        var device = new Device { Id = "1", AssetId = "rpi-001", Hostname = "node-1" };
        var mockIterator = CreateMockIterator(new List<Device> { device });
        _mockFleetContainer
            .Setup(c => c.GetItemQueryIterator<Device>(
                It.IsAny<QueryDefinition>(),
                It.IsAny<string?>(),
                It.IsAny<QueryRequestOptions?>()))
            .Returns(mockIterator.Object);

        var service = CreateService();
        var result = await service.GetDeviceAsync("rpi-001");

        result.Should().NotBeNull();
        result!.AssetId.Should().Be("rpi-001");
    }

    [Fact]
    public async Task GetDeviceAsync_WithInvalidAssetId_ReturnsNull()
    {
        var mockIterator = CreateMockIterator(new List<Device>());
        _mockFleetContainer
            .Setup(c => c.GetItemQueryIterator<Device>(
                It.IsAny<QueryDefinition>(),
                It.IsAny<string?>(),
                It.IsAny<QueryRequestOptions?>()))
            .Returns(mockIterator.Object);

        var service = CreateService();
        var result = await service.GetDeviceAsync("does-not-exist");

        result.Should().BeNull();
    }

    [Fact]
    public async Task GetTelemetryAsync_ReturnsOrderedTelemetry()
    {
        var records = new List<TelemetryRecord>
        {
            new TelemetryRecord { Id = "t1", AssetId = "rpi-001", Temperature = 72.1, Timestamp = DateTime.UtcNow.AddMinutes(-1) },
            new TelemetryRecord { Id = "t2", AssetId = "rpi-001", Temperature = 71.5, Timestamp = DateTime.UtcNow.AddMinutes(-2) }
        };
        var mockIterator = CreateMockIterator(records);
        _mockTelemetryContainer
            .Setup(c => c.GetItemQueryIterator<TelemetryRecord>(
                It.IsAny<QueryDefinition>(),
                It.IsAny<string?>(),
                It.IsAny<QueryRequestOptions?>()))
            .Returns(mockIterator.Object);

        var service = CreateService();
        var result = (await service.GetTelemetryAsync("rpi-001")).ToList();

        result.Should().HaveCount(2);
        result[0].Id.Should().Be("t1");
        result[1].Id.Should().Be("t2");
    }

    [Fact]
    public async Task GetImagesAsync_ReturnsImages()
    {
        var images = new List<ImageRecord>
        {
            new ImageRecord { Id = "img1", AssetId = "rpi-001", BlobUrl = "https://storage.blob.core.windows.net/device-images/img1.jpg", CapturedAt = DateTime.UtcNow.AddMinutes(-5) },
            new ImageRecord { Id = "img2", AssetId = "rpi-001", BlobUrl = "https://storage.blob.core.windows.net/device-images/img2.jpg", CapturedAt = DateTime.UtcNow.AddMinutes(-10) }
        };
        var mockIterator = CreateMockIterator(images);
        _mockImagesContainer
            .Setup(c => c.GetItemQueryIterator<ImageRecord>(
                It.IsAny<QueryDefinition>(),
                It.IsAny<string?>(),
                It.IsAny<QueryRequestOptions?>()))
            .Returns(mockIterator.Object);

        var service = CreateService();
        var result = (await service.GetImagesAsync("rpi-001")).ToList();

        result.Should().HaveCount(2);
        result[0].Id.Should().Be("img1");
        result[1].Id.Should().Be("img2");
    }
}
