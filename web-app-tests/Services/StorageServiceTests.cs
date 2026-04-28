using Xunit;
using Azure.Storage.Blobs;
using Microsoft.Extensions.Logging;
using Moq;
using FluentAssertions;
using WebApp.Services;

namespace WebAppTests.Services;

public class StorageServiceTests
{
    private const string ContainerName = "device-images";

    private static (StorageService service, Mock<BlobServiceClient> mockBlobServiceClient) CreateService()
    {
        var mockBlobServiceClient = new Mock<BlobServiceClient>();
        var service = new StorageService(
            mockBlobServiceClient.Object,
            Mock.Of<ILogger<StorageService>>());
        return (service, mockBlobServiceClient);
    }

    [Fact]
    public async Task GetImageUrlAsync_ReturnsCorrectUrl()
    {
        var (service, mockBlobServiceClient) = CreateService();
        const string blobName = "rpi-001/snapshot-2024-01-15T10-30-00.jpg";
        var expectedUri = new Uri($"https://mystorage.blob.core.windows.net/{ContainerName}/{blobName}");

        var realBlobClient = new BlobClient(expectedUri);
        var mockContainerClient = new Mock<BlobContainerClient>();
        mockContainerClient
            .Setup(c => c.GetBlobClient(blobName))
            .Returns(realBlobClient);
        mockBlobServiceClient
            .Setup(s => s.GetBlobContainerClient(ContainerName))
            .Returns(mockContainerClient.Object);

        var result = await service.GetImageUrlAsync(blobName);

        result.Should().Be(expectedUri.ToString());
    }

    [Fact]
    public async Task GetImageUrlAsync_AlwaysQueriesDeviceImagesContainer()
    {
        var (service, mockBlobServiceClient) = CreateService();
        const string blobName = "test.jpg";
        var blobUri = new Uri($"https://mystorage.blob.core.windows.net/{ContainerName}/{blobName}");

        var mockContainerClient = new Mock<BlobContainerClient>();
        mockContainerClient.Setup(c => c.GetBlobClient(blobName)).Returns(new BlobClient(blobUri));
        mockBlobServiceClient
            .Setup(s => s.GetBlobContainerClient(ContainerName))
            .Returns(mockContainerClient.Object);

        await service.GetImageUrlAsync(blobName);

        mockBlobServiceClient.Verify(s => s.GetBlobContainerClient(ContainerName), Times.Once);
    }

    [Fact]
    public async Task GetImageUrlAsync_WhenExceptionThrown_ReturnsEmptyString()
    {
        var (service, mockBlobServiceClient) = CreateService();
        mockBlobServiceClient
            .Setup(s => s.GetBlobContainerClient(It.IsAny<string>()))
            .Throws(new InvalidOperationException("Storage unavailable"));

        var result = await service.GetImageUrlAsync("any-blob.jpg");

        result.Should().BeEmpty();
    }

    [Fact]
    public async Task GetImageUrlAsync_ReturnsBlobUriAsString()
    {
        var (service, mockBlobServiceClient) = CreateService();
        const string blobName = "device-snapshot.jpg";
        var blobUri = new Uri($"https://account.blob.core.windows.net/{ContainerName}/{blobName}");

        var mockContainerClient = new Mock<BlobContainerClient>();
        mockContainerClient.Setup(c => c.GetBlobClient(blobName)).Returns(new BlobClient(blobUri));
        mockBlobServiceClient
            .Setup(s => s.GetBlobContainerClient(ContainerName))
            .Returns(mockContainerClient.Object);

        var result = await service.GetImageUrlAsync(blobName);

        result.Should().StartWith("https://");
        result.Should().Contain(blobName);
    }
}
