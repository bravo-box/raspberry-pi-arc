using Azure.Storage;
using Azure.Storage.Blobs;
using FleetWebApp.Services;
using Microsoft.Azure.Cosmos;

var builder = WebApplication.CreateBuilder(args);

// ---------------------------------------------------------------------------
// MVC
// ---------------------------------------------------------------------------
builder.Services.AddControllersWithViews();

// ---------------------------------------------------------------------------
// Cosmos DB (singleton – thread-safe, expensive to construct)
// ---------------------------------------------------------------------------
builder.Services.AddSingleton(sp =>
{
    var cfg      = sp.GetRequiredService<IConfiguration>();
    var endpoint = cfg["CosmosDb:Endpoint"]
        ?? throw new InvalidOperationException("CosmosDb:Endpoint is required.");
    var key      = cfg["CosmosDb:AccountKey"]
        ?? throw new InvalidOperationException("CosmosDb:AccountKey is required.");

    return new CosmosClient(endpoint, key, new CosmosClientOptions
    {
        SerializerOptions = new CosmosSerializationOptions
        {
            PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase
        }
    });
});

// ---------------------------------------------------------------------------
// Azure Blob Storage (for SAS URL generation)
// ---------------------------------------------------------------------------
builder.Services.AddSingleton(sp =>
{
    var cfg         = sp.GetRequiredService<IConfiguration>();
    var accountName = cfg["Storage:AccountName"]
        ?? throw new InvalidOperationException("Storage:AccountName is required.");
    var accountKey  = cfg["Storage:AccountKey"]
        ?? throw new InvalidOperationException("Storage:AccountKey is required.");

    var credential = new StorageSharedKeyCredential(accountName, accountKey);
    // Azure Government storage endpoint
    var blobEndpoint = new Uri($"https://{accountName}.blob.core.usgovcloudapi.net");
    return new BlobServiceClient(blobEndpoint, credential);
});

// ---------------------------------------------------------------------------
// Application services
// ---------------------------------------------------------------------------
builder.Services.AddSingleton<IFleetRepository, CosmosFleetRepository>();
builder.Services.AddSingleton<IBlobUrlService, BlobUrlService>();

// ---------------------------------------------------------------------------
// Build & run
// ---------------------------------------------------------------------------
var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Devices}/{action=Index}/{id?}");

app.Run();
