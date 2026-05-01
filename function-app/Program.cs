using Azure.Messaging.ServiceBus;
using FleetFunctionApp.Services;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices((context, services) =>
    {
        // Cosmos DB client (singleton – thread-safe and expensive to create)
        services.AddSingleton(sp =>
        {
            var endpoint = context.Configuration["CosmosDb__Endpoint"]
                ?? throw new InvalidOperationException("CosmosDb__Endpoint is not configured.");
            var key = context.Configuration["CosmosDb__AccountKey"]
                ?? throw new InvalidOperationException("CosmosDb__AccountKey is not configured.");

            return new CosmosClient(endpoint, key, new CosmosClientOptions
            {
                SerializerOptions = new CosmosSerializationOptions
                {
                    PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase
                }
            });
        });

        // Service Bus client used to send photo-processed acknowledgements
        services.AddSingleton(sp =>
        {
            var connectionString = context.Configuration["ServiceBusConnection"]
                ?? throw new InvalidOperationException("ServiceBusConnection is not configured.");
            return new ServiceBusClient(connectionString);
        });

        // Fleet repository
        services.AddSingleton<IFleetRepository, CosmosFleetRepository>();
    })
    .Build();

host.Run();
