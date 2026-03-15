const { Kafka } = require('kafkajs');
const fs = require('fs');

const kafkaBroker = process.env.KAFKA_BROKER || 'localhost:9092';

// Parse command line arguments
function parseArgs() {
  const args = {};
  const argList = process.argv.slice(2);

  for (let i = 0; i < argList.length; i += 2) {
    const key = argList[i].replace(/^--/, '');
    const value = argList[i + 1];
    args[key] = value;
  }

  return args;
}

async function publishEvent() {
  const args = parseArgs();

  if (!args.event || !args.tenant) {
    console.error('Usage: node notify.js --event <EVENT_NAME> --tenant <TENANT_NAME> [--version <VERSION>]');
    process.exit(1);
  }

  const event = {
    event: args.event,
    tenant: args.tenant,
    domain: `${args.tenant}.example.com`,
    timestamp: new Date().toISOString(),
    version: args.version || 'unknown'
  };

  const kafka = new Kafka({
    clientId: 'ci-notifier',
    brokers: [kafkaBroker],
    retry: {
      initialRetryTime: 100,
      retries: 8
    }
  });

  const producer = kafka.producer();

  try {
    console.log(`Publishing event to Kafka at ${kafkaBroker}...`);
    await producer.connect();

    const result = await producer.send({
      topic: 'website-events',
      messages: [
        {
          key: event.tenant,
          value: JSON.stringify(event),
          timestamp: Date.now().toString()
        }
      ]
    });

    console.log(`✓ Event published successfully:`, event);
    await producer.disconnect();

  } catch (err) {
    console.error(`✗ Failed to publish event: ${err.message}`);
    process.exit(1);
  }
}

publishEvent();
