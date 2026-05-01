namespace FleetWebApp.Services;

/// <summary>
/// Generates time-limited, read-only User Delegation SAS URLs for blobs stored
/// in Azure Blob Storage using the application's system-assigned managed identity.
/// No storage account key is required at runtime.
/// </summary>
public interface IBlobUrlService
{
    /// <summary>
    /// Returns a read-only User Delegation SAS URL for the specified blob, valid
    /// for <paramref name="validForMinutes"/> minutes.
    /// </summary>
    Task<string> GetSasUrlAsync(string containerName, string blobName, int validForMinutes = 60);
}
