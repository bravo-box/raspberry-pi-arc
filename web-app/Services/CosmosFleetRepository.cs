using FleetWebApp.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Configuration;

namespace FleetWebApp.Services;

/// <summary>Cosmos DB implementation of <see cref="IFleetRepository"/>.</summary>
public sealed class CosmosFleetRepository : IFleetRepository
{
    private readonly Container _devices;
    private readonly Container _images;

    public CosmosFleetRepository(CosmosClient cosmosClient, IConfiguration configuration)
    {
        var databaseName = configuration["CosmosDb:DatabaseName"] ?? "fleet";
        var db           = cosmosClient.GetDatabase(databaseName);
        _devices         = db.GetContainer("devices");
        _images          = db.GetContainer("images");
    }

    public async Task<IReadOnlyList<Device>> GetAllDevicesAsync(
        CancellationToken cancellationToken = default)
    {
        var query   = new QueryDefinition("SELECT * FROM c ORDER BY c.hostname ASC");
        var results = new List<Device>();

        using var iterator = _devices.GetItemQueryIterator<Device>(query);
        while (iterator.HasMoreResults)
        {
            var page = await iterator.ReadNextAsync(cancellationToken);
            results.AddRange(page);
        }

        return results;
    }

    public async Task<Device?> GetDeviceAsync(
        string hostname, CancellationToken cancellationToken = default)
    {
        try
        {
            var response = await _devices.ReadItemAsync<Device>(
                hostname, new PartitionKey(hostname), cancellationToken: cancellationToken);
            return response.Resource;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<IReadOnlyList<DeviceImage>> GetDeviceImagesAsync(
        string hostname, CancellationToken cancellationToken = default)
    {
        var query = new QueryDefinition(
            "SELECT * FROM c WHERE c.hostName = @hostname ORDER BY c.uploadedAt DESC")
            .WithParameter("@hostname", hostname);

        var results = new List<DeviceImage>();

        using var iterator = _images.GetItemQueryIterator<DeviceImage>(
            query, requestOptions: new QueryRequestOptions
            {
                PartitionKey = new PartitionKey(hostname)
            });

        while (iterator.HasMoreResults)
        {
            var page = await iterator.ReadNextAsync(cancellationToken);
            results.AddRange(page);
        }

        return results;
    }
}
