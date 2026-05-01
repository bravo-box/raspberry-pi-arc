namespace FleetWebApp.Services;

/// <summary>
/// Generates time-limited SAS URLs for blobs stored in Azure Blob Storage.
/// </summary>
public interface IBlobUrlService
{
    /// <summary>
    /// Returns a read-only SAS URL for the specified blob, valid for
    /// <paramref name="validForMinutes"/> minutes.
    /// </summary>
    string GetSasUrl(string containerName, string blobName, int validForMinutes = 60);
}
