using Microsoft.Azure.Cosmos;
using WebApp.Models;

namespace WebApp.Services;

public interface ICosmosDbService
{
    Task<IEnumerable<Device>> GetAllDevicesAsync();
    Task<Device?> GetDeviceAsync(string assetId);
    Task<IEnumerable<TelemetryRecord>> GetTelemetryAsync(string assetId, int maxRecords = 100);
    Task<IEnumerable<ImageRecord>> GetImagesAsync(string assetId);
}

public class CosmosDbService : ICosmosDbService
{
    private readonly Container _fleetContainer;
    private readonly Container _telemetryContainer;
    private readonly Container _imagesContainer;
    private readonly ILogger<CosmosDbService> _logger;

    public CosmosDbService(
        CosmosClient cosmosClient,
        IConfiguration configuration,
        ILogger<CosmosDbService> logger)
    {
        _logger = logger;

        var databaseName = configuration["CosmosDb:DatabaseName"] ?? "rpi-arc";
        var fleetContainer = configuration["CosmosDb:FleetContainer"] ?? "fleet";
        var telemetryContainer = configuration["CosmosDb:TelemetryContainer"] ?? "telemetry";
        var imagesContainer = configuration["CosmosDb:ImagesContainer"] ?? "images";

        var database = cosmosClient.GetDatabase(databaseName);
        _fleetContainer = database.GetContainer(fleetContainer);
        _telemetryContainer = database.GetContainer(telemetryContainer);
        _imagesContainer = database.GetContainer(imagesContainer);
    }

    public async Task<IEnumerable<Device>> GetAllDevicesAsync()
    {
        var devices = new List<Device>();
        try
        {
            var query = new QueryDefinition("SELECT * FROM c");
            using var iterator = _fleetContainer.GetItemQueryIterator<Device>(query);
            while (iterator.HasMoreResults)
            {
                var response = await iterator.ReadNextAsync();
                devices.AddRange(response);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching all devices from Cosmos DB");
        }
        return devices;
    }

    public async Task<Device?> GetDeviceAsync(string assetId)
    {
        try
        {
            var query = new QueryDefinition("SELECT * FROM c WHERE c.assetId = @assetId")
                .WithParameter("@assetId", assetId);
            using var iterator = _fleetContainer.GetItemQueryIterator<Device>(query);
            while (iterator.HasMoreResults)
            {
                var response = await iterator.ReadNextAsync();
                var device = response.FirstOrDefault();
                if (device is not null)
                    return device;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching device {AssetId} from Cosmos DB", assetId);
        }
        return null;
    }

    public async Task<IEnumerable<TelemetryRecord>> GetTelemetryAsync(string assetId, int maxRecords = 100)
    {
        var records = new List<TelemetryRecord>();
        try
        {
            var query = new QueryDefinition(
                "SELECT TOP @max * FROM c WHERE c.assetId = @assetId ORDER BY c.timestamp DESC")
                .WithParameter("@max", maxRecords)
                .WithParameter("@assetId", assetId);
            using var iterator = _telemetryContainer.GetItemQueryIterator<TelemetryRecord>(query);
            while (iterator.HasMoreResults)
            {
                var response = await iterator.ReadNextAsync();
                records.AddRange(response);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching telemetry for {AssetId}", assetId);
        }
        return records;
    }

    public async Task<IEnumerable<ImageRecord>> GetImagesAsync(string assetId)
    {
        var images = new List<ImageRecord>();
        try
        {
            var query = new QueryDefinition(
                "SELECT * FROM c WHERE c.assetId = @assetId ORDER BY c.capturedAt DESC")
                .WithParameter("@assetId", assetId);
            using var iterator = _imagesContainer.GetItemQueryIterator<ImageRecord>(query);
            while (iterator.HasMoreResults)
            {
                var response = await iterator.ReadNextAsync();
                images.AddRange(response);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching images for {AssetId}", assetId);
        }
        return images;
    }
}
