const { Kafka } = require('kafkajs');

const kafkaBroker = process.env.KAFKA_BROKER || 'localhost:9092';
const kafka = new Kafka({
  clientId: 'event-consumer',
  brokers: [kafkaBroker],
  retry: {
    initialRetryTime: 100,
    retries: 8
  }
});

const consumer = kafka.consumer({ groupId: 'verifier-group' });

async function run() {
  console.log(`Connecting to Kafka at ${kafkaBroker}...`);

  try {
    await consumer.connect();
    console.log('✓ Connected to Kafka');

    await consumer.subscribe({ topic: 'website-events', fromBeginning: true });
    console.log('✓ Subscribed to topic: website-events');
    console.log('Waiting for messages...\n');

    let eventCount = 0;

    await consumer.run({
      eachMessage: async ({ topic, partition, message }) => {
        eventCount++;
        const event = JSON.parse(message.value.toString());

        console.log(`\n[Event #${eventCount}]`);
        console.log(`  Topic: ${topic}`);
        console.log(`  Partition: ${partition}`);
        console.log(`  Key: ${message.key ? message.key.toString() : 'null'}`);
        console.log(`  Event Type: ${event.event}`);
        console.log(`  Tenant: ${event.tenant}`);
        console.log(`  Domain: ${event.domain}`);
        console.log(`  Timestamp: ${event.timestamp}`);
        console.log(`  Version: ${event.version}`);
      }
    });
  } catch (err) {
    console.error('Error:', err.message);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('\n\nShutting down consumer...');
  await consumer.disconnect();
  process.exit(0);
});

run();
