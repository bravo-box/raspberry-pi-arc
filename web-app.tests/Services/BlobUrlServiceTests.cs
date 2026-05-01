using Azure;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using FleetWebApp.Services;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace FleetWebApp.Tests.Services;

/// <summary>
/// Unit tests for <see cref="BlobUrlService"/>.
///
/// These tests exercise the User Delegation Key caching logic.  The actual SAS
/// signature is computed by the Azure SDK using a 32-byte zero key (valid Base64,
/// produces a computable HMAC).  The resulting SAS URL is not a real Azure
/// credential — it is only used to verify that the service builds a non-empty URL.
/// </summary>
public sealed class BlobUrlServiceTests
{
    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private static UserDelegationKey CreateFakeKey(DateTimeOffset expiresOn) =>
        // Use positional args to resolve the ambiguous overload:
        // (signedObjectId, signedTenantId, signedStartsOn, signedExpiresOn, signedService, signedVersion, value)
        BlobsModelFactory.UserDelegationKey(
            "00000000-0000-0000-0000-000000000001",
            "00000000-0000-0000-0000-000000000002",
            DateTimeOffset.UtcNow.AddMinutes(-1),
            expiresOn,
            "b",
            "2020-12-06",
            Convert.ToBase64String(new byte[32]));

    private static Mock<Response<UserDelegationKey>> KeyResponse(UserDelegationKey key)
    {
        var mock = new Mock<Response<UserDelegationKey>>();
        mock.Setup(r => r.Value).Returns(key);
        return mock;
    }

    private static Mock<BlobServiceClient> BuildBlobServiceClient(
        Func<Mock<BlobServiceClient>, Response<UserDelegationKey>>? keySetup = null)
    {
        var key            = CreateFakeKey(DateTimeOffset.UtcNow.AddHours(2));
        var mockKeyResp    = KeyResponse(key);
        var mockBlobClient = new Mock<BlobClient>();

        // Provide a valid Azure Blob Storage URI so BlobUriBuilder can parse it.
        mockBlobClient.Setup(b => b.Uri)
                      .Returns(new Uri("https://testaccount.blob.core.windows.net/photos/test.jpg"));

        var mockContainer = new Mock<BlobContainerClient>();
        mockContainer.Setup(c => c.GetBlobClient(It.IsAny<string>()))
                     .Returns(mockBlobClient.Object);

        var mockClient = new Mock<BlobServiceClient>();
        mockClient.Setup(c => c.GetBlobContainerClient(It.IsAny<string>()))
                  .Returns(mockContainer.Object);
        mockClient.Setup(c => c.GetUserDelegationKeyAsync(
                      It.IsAny<DateTimeOffset?>(),
                      It.IsAny<DateTimeOffset>(),
                      It.IsAny<CancellationToken>()))
                  .ReturnsAsync(mockKeyResp.Object);

        return mockClient;
    }

    private static BlobUrlService BuildService(Mock<BlobServiceClient> mockClient) =>
        new(mockClient.Object, "testaccount", NullLogger<BlobUrlService>.Instance);

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------

    [Fact]
    public async Task GetSasUrlAsync_ReturnsNonEmptyUrl()
    {
        var mockClient = BuildBlobServiceClient();
        using var svc  = BuildService(mockClient);

        var url = await svc.GetSasUrlAsync("photos", "test.jpg", 60);

        Assert.False(string.IsNullOrEmpty(url));
    }

    [Fact]
    public async Task GetSasUrlAsync_ReturnedUrl_ContainsAccountName()
    {
        var mockClient = BuildBlobServiceClient();
        using var svc  = BuildService(mockClient);

        var url = await svc.GetSasUrlAsync("photos", "test.jpg", 60);

        Assert.Contains("testaccount", url);
    }

    [Fact]
    public async Task GetSasUrlAsync_FirstCall_FetchesDelegationKeyOnce()
    {
        var mockClient = BuildBlobServiceClient();
        using var svc  = BuildService(mockClient);

        _ = await svc.GetSasUrlAsync("photos", "test.jpg", 60);

        mockClient.Verify(c => c.GetUserDelegationKeyAsync(
            It.IsAny<DateTimeOffset?>(),
            It.IsAny<DateTimeOffset>(),
            It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task GetSasUrlAsync_WhenCachedKeyIsValid_DoesNotRefetch()
    {
        var mockClient = BuildBlobServiceClient();
        using var svc  = BuildService(mockClient);

        _ = await svc.GetSasUrlAsync("photos", "first.jpg",  60);
        _ = await svc.GetSasUrlAsync("photos", "second.jpg", 60);

        // Key should only be fetched once; the second call uses the cached key.
        mockClient.Verify(c => c.GetUserDelegationKeyAsync(
            It.IsAny<DateTimeOffset?>(),
            It.IsAny<DateTimeOffset>(),
            It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task GetSasUrlAsync_WhenSasWouldOutliveKey_RefetchesKey()
    {
        // First call requests a 30-minute SAS → service caches a key valid for
        // 30 + 10 (KeyRefreshMarginMinutes) = 40 minutes.
        // Second call requests a 60-minute SAS → the cached key only covers 40 minutes,
        // so the service must fetch a new, longer-lived key.
        var freshResp1 = KeyResponse(CreateFakeKey(DateTimeOffset.UtcNow.AddHours(1)));
        var freshResp2 = KeyResponse(CreateFakeKey(DateTimeOffset.UtcNow.AddHours(2)));

        var mockBlobClient = new Mock<BlobClient>();
        mockBlobClient.Setup(b => b.Uri)
                      .Returns(new Uri("https://testaccount.blob.core.windows.net/photos/test.jpg"));
        var mockContainer = new Mock<BlobContainerClient>();
        mockContainer.Setup(c => c.GetBlobClient(It.IsAny<string>())).Returns(mockBlobClient.Object);

        var mockSvc = new Mock<BlobServiceClient>();
        mockSvc.Setup(c => c.GetBlobContainerClient(It.IsAny<string>())).Returns(mockContainer.Object);
        mockSvc.SetupSequence(c => c.GetUserDelegationKeyAsync(
                    It.IsAny<DateTimeOffset?>(),
                    It.IsAny<DateTimeOffset>(),
                    It.IsAny<CancellationToken>()))
               .ReturnsAsync(freshResp1.Object)
               .ReturnsAsync(freshResp2.Object);

        using var svc = BuildService(mockSvc);

        // 30-minute SAS → key cached for 40 min (30 + 10 margin)
        _ = await svc.GetSasUrlAsync("photos", "first.jpg", 30);
        // 60-minute SAS → cached key only lasts 40 min, must re-fetch
        _ = await svc.GetSasUrlAsync("photos", "second.jpg", 60);

        mockSvc.Verify(c => c.GetUserDelegationKeyAsync(
            It.IsAny<DateTimeOffset?>(),
            It.IsAny<DateTimeOffset>(),
            It.IsAny<CancellationToken>()), Times.Exactly(2));
    }

    [Fact]
    public async Task GetSasUrlAsync_MultipleConcurrentCalls_FetchesKeyOnlyOnce()
    {
        var mockClient = BuildBlobServiceClient();
        using var svc  = BuildService(mockClient);

        // Fire 10 concurrent requests; only the first should trigger a key fetch.
        var tasks = Enumerable.Range(1, 10)
            .Select(i => svc.GetSasUrlAsync("photos", $"img{i}.jpg", 60));

        await Task.WhenAll(tasks);

        mockClient.Verify(c => c.GetUserDelegationKeyAsync(
            It.IsAny<DateTimeOffset?>(),
            It.IsAny<DateTimeOffset>(),
            It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public void Dispose_CanBeCalledMultipleTimes_DoesNotThrow()
    {
        var mockClient = BuildBlobServiceClient();
        var svc        = BuildService(mockClient);

        svc.Dispose();
        // A second Dispose should not throw.
        var ex = Record.Exception(() => svc.Dispose());
        Assert.Null(ex);
    }
}
