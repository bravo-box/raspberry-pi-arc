using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace FleetFunctionApp.Functions;

/// <summary>
/// Triggered by every message published to the <c>TaskCamera</c> Service Bus
/// topic (subscription: <c>cloud-monitor</c>).
///
/// Cloud-side audit log: records that a camera-capture command was issued to a
/// Pi device.  Extend this function to add command telemetry, rate limiting, or
/// dead-letter alerting as needed.
/// </summary>
public sealed class TaskCameraFunction
{
    private readonly ILogger<TaskCameraFunction> _logger;

    public TaskCameraFunction(ILogger<TaskCameraFunction> logger)
    {
        _logger = logger;
    }

    [Function(nameof(TaskCameraFunction))]
    public Task RunAsync(
        [ServiceBusTrigger("TaskCamera", "cloud-monitor",
            Connection = "ServiceBusConnection")]
        string messageBody,
        FunctionContext context)
    {
        _logger.LogInformation(
            "TaskCamera command issued. MessageBody: {Body}", messageBody);

        return Task.CompletedTask;
    }
}
