using System.Text.Json;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.ServiceBus;
using Microsoft.Extensions.Logging;

public static class ProcessOrder
{
    [FunctionName("ProcessOrder")]
    public static async Task Run(
        [ServiceBusTrigger("%ORDER_QUEUE%", Connection = "AzureWebJobsServiceBus", IsSessionsEnabled = true)]
        string messageBody,
        string messageId,
        string sessionId,
        IDictionary<string, object> applicationProperties,
        ILogger log)
    {
        var step = applicationProperties.TryGetValue("Step", out var s) ? s?.ToString() : "Unknown";
        var order = JsonSerializer.Deserialize<Order>(messageBody);

        try
        {
            log.LogInformation("Processing {Step} for Order {OrderId}", step, order?.OrderId);
            // TODO: check idempotency store, then call services.
            await Task.CompletedTask;
        }
        catch (Exception ex)
        {
            log.LogError(ex, "Failed processing Order {OrderId}", order?.OrderId);
            throw; // Let runtime retry and eventually DLQ
        }
    }

    public record Order(string OrderId, decimal Amount, string CustomerId);
}
