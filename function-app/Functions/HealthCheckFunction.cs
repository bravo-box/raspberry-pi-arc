using FleetFunctionApp.Models;
using FleetFunctionApp.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Text.Json;

namespace FleetFunctionApp.Functions;

/// <summary>
/// Triggered by every message published to the <c>health-check</c> Service Bus
/// topic (subscription: <c>health-function</c>).
///
/// Responsibilities:
/// <list type="number">
///   <item>Parse the health-check heartbeat from the Pi device.</item>
///   <item>Persist the record to the Cosmos DB <c>health-checks</c> container.</item>
/// </list>
/// </summary>
public sealed class HealthCheckFunction
{
    private readonly IFleetRepository _repository;
    private readonly ILogger<HealthCheckFunction> _logger;

    public HealthCheckFunction(
        IFleetRepository repository,
        ILogger<HealthCheckFunction> logger)
    {
        _repository = repository;
        _logger     = logger;
    }

    [Function(nameof(HealthCheckFunction))]
    public async Task RunAsync(
        [ServiceBusTrigger("health-check", "health-function",
            Connection = "ServiceBusConnection")]
        string messageBody,
        FunctionContext context)
    {
        _logger.LogInformation("health-check message received: {Body}", messageBody);

        HealthCheckMessage? message;
        try
        {
            var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
            message = JsonSerializer.Deserialize<HealthCheckMessage>(messageBody, options);
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex, "Failed to deserialise health-check message body.");
            return;
        }

        if (message is null || string.IsNullOrWhiteSpace(message.DeviceId))
        {
            _logger.LogWarning("health-check message is missing the device_id field; skipping.");
            return;
        }

        var record = new HealthCheckRecord
        {
            // Unique ID combines device ID and timestamp for idempotency.
            Id             = $"{message.DeviceId}_{message.Timestamp:yyyyMMddTHHmmssfffZ}",
            DeviceId       = message.DeviceId,
            Hostname       = message.Hostname,
            NetworkStatus  = message.NetworkStatus,
            DiskTotalGb    = message.DiskTotalGb,
            DiskUsedGb     = message.DiskUsedGb,
            DiskFreeGb     = message.DiskFreeGb,
            DiskFreePercent = message.DiskFreePercent,
            Status         = message.Status,
            Timestamp      = message.Timestamp,
            ReceivedAt     = DateTimeOffset.UtcNow
        };

        await _repository.SaveHealthCheckAsync(record);

        _logger.LogInformation(
            "Saved health-check for device {DeviceId} (status={Status}, network={Network}, diskFree={DiskFree:F1}%)",
            record.DeviceId, record.Status, record.NetworkStatus, record.DiskFreePercent);
    }
}
