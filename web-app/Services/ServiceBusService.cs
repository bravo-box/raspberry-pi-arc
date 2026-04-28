using System.Text;
using System.Text.Json;
using Azure.Messaging.ServiceBus;

namespace WebApp.Services;

public interface IServiceBusService
{
    Task SendTakePictureCommandAsync(string assetId);
}

public class ServiceBusService : IServiceBusService
{
    private readonly ServiceBusSender _sender;
    private readonly ILogger<ServiceBusService> _logger;

    public ServiceBusService(ServiceBusClient serviceBusClient, IConfiguration configuration, ILogger<ServiceBusService> logger)
    {
        _logger = logger;
        var topic = configuration["ServiceBus:CommandsTopic"] ?? "device-commands";
        _sender = serviceBusClient.CreateSender(topic);
    }

    public async Task SendTakePictureCommandAsync(string assetId)
    {
        try
        {
            var payload = JsonSerializer.Serialize(new { command = "take-picture", assetId });
            var message = new ServiceBusMessage(Encoding.UTF8.GetBytes(payload))
            {
                ContentType = "application/json"
            };
            await _sender.SendMessageAsync(message);
            _logger.LogInformation("Sent take-picture command for device {AssetId}", assetId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error sending take-picture command for {AssetId}", assetId);
            throw;
        }
    }
}
