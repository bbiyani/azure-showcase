using System.Text.Json;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.ServiceBus;
using Microsoft.Extensions.Logging;
using Azure.Messaging.ServiceBus;

public class DlqRepair
{
    private readonly ServiceBusClient _client;
    private readonly string _queue;

    public DlqRepair()
    {
        _client = new ServiceBusClient(Environment.GetEnvironmentVariable("AzureWebJobsServiceBus"));
        _queue = Environment.GetEnvironmentVariable("ORDER_QUEUE") ?? "order-processing";
    }

    [FunctionName("RepairDlq")]
    public async Task Run(
        [ServiceBusTrigger("%ORDER_QUEUE%/$DeadLetterQueue", Connection = "AzureWebJobsServiceBus")]
        ServiceBusReceivedMessage dead,
        ILogger log)
    {
        var reason = dead.DeadLetterReason;
        var desc = dead.DeadLetterErrorDescription;
        log.LogWarning("DLQ message detected. Reason={Reason}, Description={Desc}, MessageId={Id}", reason, desc, dead.MessageId);

        // naive example: resubmit once for transient issues
        if (reason?.Contains("Transient", StringComparison.OrdinalIgnoreCase) == true)
        {
            var sender = _client.CreateSender(_queue);
            var newMsg = new ServiceBusMessage(dead.Body)
            {
                MessageId = dead.MessageId,
                SessionId = dead.SessionId
            };
            foreach (var kv in dead.ApplicationProperties)
                newMsg.ApplicationProperties[kv.Key] = kv.Value;
            await sender.SendMessageAsync(newMsg);
            log.LogInformation("Resubmitted {Id} to {Queue}", dead.MessageId, _queue);
        }
        else
        {
            log.LogWarning("Parking message {Id}. Inspect and fix manually.", dead.MessageId);
        }
    }
}
