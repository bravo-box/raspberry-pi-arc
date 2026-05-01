namespace FleetWebApp.Models;

/// <summary>Represents metadata for a camera image uploaded by a Pi device.</summary>
public sealed class DeviceImage
{
    public string Id { get; set; } = string.Empty;
    public string HostName { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public string StorageAccount { get; set; } = string.Empty;
    public string Container { get; set; } = string.Empty;
    public DateTimeOffset UploadedAt { get; set; }

    /// <summary>
    /// Time-limited SAS URL for displaying the image in the browser.
    /// Populated by <c>BlobUrlService</c> before the view is rendered.
    /// </summary>
    public string? ImageUrl { get; set; }
}
