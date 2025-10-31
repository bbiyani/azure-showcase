using System.Text;
using Azure.Identity;
using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Producer;

var eventHubName = Environment.GetEnvironmentVariable("EVENTHUB_NAME") ?? "retail-telemetry";
var fqns = Environment.GetEnvironmentVariable("EVENTHUB_FQNS") ?? throw new InvalidOperationException("EVENTHUB_FQNS not set");

var producer = new EventHubProducerClient(fqns, eventHubName, new DefaultAzureCredential());
using var batch = await producer.CreateBatchAsync();

batch.TryAdd(new EventData(Encoding.UTF8.GetBytes("metric:pageView")));
batch.TryAdd(new EventData(Encoding.UTF8.GetBytes("metric:orderViewed:12345")));

await producer.SendAsync(batch);
Console.WriteLine("Telemetry batch sent");
