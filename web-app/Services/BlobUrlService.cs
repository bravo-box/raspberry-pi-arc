using Azure.Storage.Blobs;
using Azure.Storage.Sas;

namespace FleetWebApp.Services;

/// <summary>
/// Azure Blob Storage implementation of <see cref="IBlobUrlService"/>.
/// Generates time-limited, read-only SAS URLs suitable for embedding in HTML
/// image tags so the browser can display photos directly from blob storage.
/// </summary>
public sealed class BlobUrlService : IBlobUrlService
{
    private readonly BlobServiceClient _blobServiceClient;

    public BlobUrlService(BlobServiceClient blobServiceClient)
    {
        _blobServiceClient = blobServiceClient;
    }

    public string GetSasUrl(string containerName, string blobName, int validForMinutes = 60)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(containerName);
        var blobClient      = containerClient.GetBlobClient(blobName);

        if (!blobClient.CanGenerateSasUri)
        {
            // Fall back to the plain blob URI if SAS generation is unavailable
            // (e.g. when using a connection string without a shared key).
            return blobClient.Uri.ToString();
        }

        var sasBuilder = new BlobSasBuilder
        {
            BlobContainerName = containerName,
            BlobName          = blobName,
            Resource          = "b",
            ExpiresOn         = DateTimeOffset.UtcNow.AddMinutes(validForMinutes)
        };
        sasBuilder.SetPermissions(BlobSasPermissions.Read);

        return blobClient.GenerateSasUri(sasBuilder).ToString();
    }
}
