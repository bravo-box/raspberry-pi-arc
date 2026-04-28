using Azure.Identity;
using Azure.Storage.Blobs;

namespace WebApp.Services;

public interface IStorageService
{
    Task<string> GetImageUrlAsync(string blobName);
}

public class StorageService : IStorageService
{
    private readonly BlobServiceClient _blobServiceClient;
    private readonly ILogger<StorageService> _logger;
    private const string ContainerName = "device-images";

    public StorageService(BlobServiceClient blobServiceClient, ILogger<StorageService> logger)
    {
        _blobServiceClient = blobServiceClient;
        _logger = logger;
    }

    public Task<string> GetImageUrlAsync(string blobName)
    {
        try
        {
            var containerClient = _blobServiceClient.GetBlobContainerClient(ContainerName);
            var blobClient = containerClient.GetBlobClient(blobName);
            return Task.FromResult(blobClient.Uri.ToString());
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error building blob URL for {BlobName}", blobName);
            return Task.FromResult(string.Empty);
        }
    }
}
