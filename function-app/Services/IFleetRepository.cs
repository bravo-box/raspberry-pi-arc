using FleetFunctionApp.Models;

namespace FleetFunctionApp.Services;

/// <summary>
/// Abstracts persistence operations against Cosmos DB for the fleet data model.
/// </summary>
public interface IFleetRepository
{
    Task UpsertDeviceAsync(string hostname, CancellationToken cancellationToken = default);
    Task SaveImageAsync(ImageRecord image, CancellationToken cancellationToken = default);
}
