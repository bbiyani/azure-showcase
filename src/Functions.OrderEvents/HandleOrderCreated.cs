using System.Text.Json;
using Azure.Messaging;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.EventGrid;
using Microsoft.Extensions.Logging;

public class HandleOrderCreated
{
    private readonly ServiceBusClient _sbClient;
    private readonly string _queueName = Environment.GetEnvironmentVariable("ORDER_QUEUE") ?? "order-processing";
    private readonly string _topicName = Environment.GetEnvironmentVariable("ORDER_TOPIC") ?? "order-events";

    public HandleOrderCreated()
    {
        _sbClient = new ServiceBusClient(Environment.GetEnvironmentVariable("AzureWebJobsServiceBus"));
    }

    [FunctionName("HandleOrderCreated")]
    public async Task Run([EventGridTrigger] CloudEvent ev, ILogger log)
    {
        if (ev.Type != "OrderCreated") return;
        var order = ev.Data.ToObjectFromJson<Order>();
        log.LogInformation("OrderCreated received: {OrderId} Amount={Amount}", order.OrderId, order.Amount);

        // 1) Queue command for workflow (sessions for FIFO per OrderId)
        var qSender = _sbClient.CreateSender(_queueName);
        var qMsg = new ServiceBusMessage(JsonSerializer.Serialize(order))
        {
            MessageId = order.OrderId,
            SessionId = order.OrderId
        };
        qMsg.ApplicationProperties["Step"] = "ValidatePayment";
        await qSender.SendMessageAsync(qMsg);

        // 2) Publish to Topic with properties so SQL filters can route (e.g., high-value orders)
        var tSender = _sbClient.CreateSender(_topicName);
        var tMsg = new ServiceBusMessage(JsonSerializer.Serialize(order))
        {
            MessageId = order.OrderId,
            SessionId = order.OrderId
        };
        tMsg.ApplicationProperties["Amount"] = order.Amount;
        tMsg.ApplicationProperties["EventType"] = "OrderCreated";
        await tSender.SendMessageAsync(tMsg);
    }

    public record Order(string OrderId, decimal Amount, string CustomerId);
}
