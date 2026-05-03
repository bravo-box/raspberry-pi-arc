using FleetFunctionApp.Models;

namespace FleetFunctionApp.Services;

/// <summary>
/// Abstracts persistence operations against Cosmos DB for the fleet data model.
/// </summary>
public interface IFleetRepository
{
    Task UpsertDeviceAsync(string hostname, CancellationToken cancellationToken = default);
    Task SaveImageAsync(ImageRecord image, CancellationToken cancellationToken = default);

    /// <summary>
    /// Registers a device: creates or updates the Cosmos DB device record and
    /// returns the assigned device GUID (preserving any existing GUID).
    /// </summary>
    Task<string> RegisterDeviceAsync(string hostname, CancellationToken cancellationToken = default);

    /// <summary>Persists a health-check heartbeat to the <c>health-checks</c> container.</summary>
    Task SaveHealthCheckAsync(HealthCheckRecord healthCheck, CancellationToken cancellationToken = default);
}
