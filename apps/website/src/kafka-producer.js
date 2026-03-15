const { Kafka } = require('kafkajs');

class KafkaProducer {
  constructor(brokerUrl) {
    this.brokerUrl = brokerUrl;
    this.kafka = new Kafka({
      clientId: 'tenant-website',
      brokers: [brokerUrl]
    });
    this.producer = this.kafka.producer({ allowAutoTopicCreation: false });
  }

  async connect() {
    await this.producer.connect();
  }

  async publishEvent(event) {
    try {
      await this.producer.send({
        topic: 'website-events',
        messages: [
          {
            key: event.tenant,
            value: JSON.stringify(event),
            timestamp: Date.now().toString()
          }
        ]
      });
    } catch (err) {
      throw new Error(`Failed to publish event to Kafka: ${err.message}`);
    }
  }

  async disconnect() {
    await this.producer.disconnect();
  }
}

module.exports = KafkaProducer;
