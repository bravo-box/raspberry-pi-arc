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
    private readonly Container _healthChecks;
    private readonly ILogger<CosmosFleetRepository> _logger;

    public CosmosFleetRepository(
        CosmosClient cosmosClient,
        IConfiguration configuration,
        ILogger<CosmosFleetRepository> logger)
    {
        _logger = logger;

        var databaseName = configuration["CosmosDb__DatabaseName"] ?? "fleet";
        var database = cosmosClient.GetDatabase(databaseName);
        _devices      = database.GetContainer("devices");
        _images       = database.GetContainer("images");
        _healthChecks = database.GetContainer("health-checks");
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

    /// <summary>
    /// Creates or updates a device record for registration, preserving any
    /// existing GUID and returning the (possibly newly generated) device ID.
    /// </summary>
    public async Task<string> RegisterDeviceAsync(string hostname, CancellationToken cancellationToken = default)
    {
        DeviceRecord record;
        string deviceId;

        try
        {
            var response = await _devices.ReadItemAsync<DeviceRecord>(
                hostname, new PartitionKey(hostname), cancellationToken: cancellationToken);
            record = response.Resource;

            // Preserve existing GUID; assign one if the record pre-dates registration.
            deviceId = string.IsNullOrWhiteSpace(record.DeviceId)
                ? Guid.NewGuid().ToString()
                : record.DeviceId;

            record.DeviceId  = deviceId;
            record.LastSeen  = DateTimeOffset.UtcNow;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            deviceId = Guid.NewGuid().ToString();
            record = new DeviceRecord
            {
                Id        = hostname,
                Hostname  = hostname,
                DeviceId  = deviceId,
                FirstSeen = DateTimeOffset.UtcNow,
                LastSeen  = DateTimeOffset.UtcNow,
                ImageCount = 0
            };
        }

        await _devices.UpsertItemAsync(record, new PartitionKey(hostname),
            cancellationToken: cancellationToken);

        _logger.LogInformation(
            "Registered device {Hostname} with DeviceId {DeviceId}",
            hostname, deviceId);

        return deviceId;
    }

    /// <summary>
    /// Persists a health-check heartbeat to the <c>health-checks</c> Cosmos DB container.
    /// </summary>
    public async Task SaveHealthCheckAsync(HealthCheckRecord healthCheck, CancellationToken cancellationToken = default)
    {
        await _healthChecks.UpsertItemAsync(healthCheck, new PartitionKey(healthCheck.DeviceId),
            cancellationToken: cancellationToken);

        _logger.LogInformation(
            "Saved health-check record {Id} for device {DeviceId} (status={Status})",
            healthCheck.Id, healthCheck.DeviceId, healthCheck.Status);
    }
}
