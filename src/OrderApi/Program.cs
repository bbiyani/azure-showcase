using Azure;
using Azure.Identity;
using Azure.Messaging;
using Azure.Messaging.EventGrid;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

var topicEndpoint = Environment.GetEnvironmentVariable("EVENTGRID_TOPIC_ENDPOINT")
    ?? throw new InvalidOperationException("EVENTGRID_TOPIC_ENDPOINT not set");
var topicKey = Environment.GetEnvironmentVariable("EVENTGRID_TOPIC_KEY"); // local dev only

EventGridPublisherClient egClient = topicKey is not null
    ? new EventGridPublisherClient(new Uri(topicEndpoint), new AzureKeyCredential(topicKey))
    : new EventGridPublisherClient(new Uri(topicEndpoint), new DefaultAzureCredential());

app.MapPost("/orders", async (Order order) =>
{
    var cloudEvent = new CloudEvent("/contoso/orders", "OrderCreated", order)
    {
        Subject = $"orders/{order.OrderId}"
    };
    await egClient.SendCloudEventAsync(cloudEvent);
    return Results.Accepted($"/orders/{order.OrderId}");
});

app.Run();

public record Order(string OrderId, decimal Amount, string CustomerId);
