namespace FleetFunctionApp.Models;

/// <summary>
/// Payload published to the <c>photo-upload</c> Service Bus topic by the Pi's
/// file-service when a JPEG has been uploaded to Azure Blob Storage.
/// </summary>
public sealed class PhotoUploadMessage
{
    /// <summary>Name of the storage account holding the photo.</summary>
    public string StorageAccount { get; set; } = string.Empty;

    /// <summary>Blob container name.</summary>
    public string Container { get; set; } = string.Empty;

    /// <summary>Blob (file) name, e.g. <c>hostname_20240101T120000_000000.jpg</c>.</summary>
    public string FileName { get; set; } = string.Empty;

    /// <summary>Hostname of the Pi that captured the image.</summary>
    public string HostName { get; set; } = string.Empty;
}
