using FleetFunctionApp.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace FleetFunctionApp.Services;

/// <summary>
/// Cosmos DB implementation of <see cref="IFleetRepository"/>.
/// </summary>
public sealed class CosmosFleetRepository : IFleetRepository
{
    private readonly Container _devices;
    private readonly Container _images;
    private readonly ILogger<CosmosFleetRepository> _logger;

    public CosmosFleetRepository(
        CosmosClient cosmosClient,
        IConfiguration configuration,
        ILogger<CosmosFleetRepository> logger)
    {
        _logger = logger;

        var databaseName = configuration["CosmosDb__DatabaseName"] ?? "fleet";
        var database = cosmosClient.GetDatabase(databaseName);
        _devices = database.GetContainer("devices");
        _images  = database.GetContainer("images");
    }

    /// <summary>
    /// Creates or updates a device record, incrementing its image count and
    /// refreshing the <c>lastSeen</c> timestamp.
    /// </summary>
    public async Task UpsertDeviceAsync(string hostname, CancellationToken cancellationToken = default)
    {
        // Try to read the existing record first so we can preserve firstSeen and imageCount.
        DeviceRecord record;
        try
        {
            var response = await _devices.ReadItemAsync<DeviceRecord>(
                hostname, new PartitionKey(hostname), cancellationToken: cancellationToken);
            record = response.Resource;
            record.LastSeen = DateTimeOffset.UtcNow;
            record.ImageCount++;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            record = new DeviceRecord
            {
                Id        = hostname,
                Hostname  = hostname,
                FirstSeen = DateTimeOffset.UtcNow,
                LastSeen  = DateTimeOffset.UtcNow,
                ImageCount = 1
            };
        }

        await _devices.UpsertItemAsync(record, new PartitionKey(hostname),
            cancellationToken: cancellationToken);

        _logger.LogInformation("Upserted device record for {Hostname} (imageCount={Count})",
            hostname, record.ImageCount);
    }

    /// <summary>
    /// Persists image metadata to the <c>images</c> Cosmos DB container.
    /// </summary>
    public async Task SaveImageAsync(ImageRecord image, CancellationToken cancellationToken = default)
    {
        await _images.UpsertItemAsync(image, new PartitionKey(image.HostName),
            cancellationToken: cancellationToken);

        _logger.LogInformation("Saved image record {FileName} for device {HostName}",
            image.FileName, image.HostName);
    }
}
