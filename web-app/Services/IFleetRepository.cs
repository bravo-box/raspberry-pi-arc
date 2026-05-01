using FleetWebApp.Models;

namespace FleetWebApp.Services;

/// <summary>Abstracts data access operations for the fleet dashboard.</summary>
public interface IFleetRepository
{
    /// <summary>Returns all registered devices, ordered by hostname.</summary>
    Task<IReadOnlyList<Device>> GetAllDevicesAsync(CancellationToken cancellationToken = default);

    /// <summary>Returns a single device by hostname, or <c>null</c> if not found.</summary>
    Task<Device?> GetDeviceAsync(string hostname, CancellationToken cancellationToken = default);

    /// <summary>Returns all images uploaded by a specific device, newest first.</summary>
    Task<IReadOnlyList<DeviceImage>> GetDeviceImagesAsync(
        string hostname, CancellationToken cancellationToken = default);
}
