using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace FleetFunctionApp.Functions;

/// <summary>
/// Triggered by every message published to the <c>photo-processed</c> Service Bus
/// topic (subscription: <c>cloud-audit</c>).
///
/// Cloud-side audit log: records that a Pi device successfully received its
/// photo-processed acknowledgement and deleted the local image file.
/// Extend this function to add telemetry, SLA tracking, or alerting.
/// </summary>
public sealed class PhotoProcessedFunction
{
    private readonly ILogger<PhotoProcessedFunction> _logger;

    public PhotoProcessedFunction(ILogger<PhotoProcessedFunction> logger)
    {
        _logger = logger;
    }

    [Function(nameof(PhotoProcessedFunction))]
    public Task RunAsync(
        [ServiceBusTrigger("photo-processed", "cloud-audit",
            Connection = "ServiceBusConnection")]
        string messageBody,
        FunctionContext context)
    {
        _logger.LogInformation(
            "photo-processed acknowledgement received. MessageBody: {Body}", messageBody);

        return Task.CompletedTask;
    }
}
