using Azure.Identity;
using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Consumer;
using Azure.Storage.Blobs;

var fqns = Environment.GetEnvironmentVariable("EVENTHUB_FQNS")
 ?? throw new InvalidOperationException("EVENTHUB_FQNS not set");
var hub = Environment.GetEnvironmentVariable("EVENTHUB_NAME") ?? "retail-telemetry";
var consumerGroup = Environment.GetEnvironmentVariable("EVENTHUB_CONSUMER") ?? EventHubConsumerClient.DefaultConsumerGroupName;

await using var consumer = new EventHubConsumerClient(consumerGroup, fqns, hub, new DefaultAzureCredential());

Console.WriteLine("Listening for events. Press Ctrl+C to exit.");
await foreach (var partitionEvent in consumer.ReadEventsAsync())
{
 Console.WriteLine($"[{partitionEvent.Partition.PartitionId}] {partitionEvent.Data.EventBody}");
}
