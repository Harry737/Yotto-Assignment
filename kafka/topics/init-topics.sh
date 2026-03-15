#!/bin/bash

set -e

KAFKA_CONTAINER="kafka_kafka_1"
TIMEOUT=30

echo "Waiting for Kafka to be healthy..."
for i in $(seq 1 $TIMEOUT); do
  if docker exec "$KAFKA_CONTAINER" \
    kafka-broker-api-versions --bootstrap-server localhost:9092 &>/dev/null; then
    echo "✓ Kafka is healthy"
    break
  fi
  if [ $i -eq $TIMEOUT ]; then
    echo "✗ Kafka did not become healthy within ${TIMEOUT}s"
    exit 1
  fi
  echo "  Waiting... ($i/$TIMEOUT)"
  sleep 1
done

echo "Creating topic: website-events"
docker exec "$KAFKA_CONTAINER" \
  kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic website-events \
  --partitions 3 \
  --replication-factor 1 \
  --if-not-exists

echo "✓ Topic 'website-events' created successfully"

echo ""
echo "Listing topics:"
docker exec "$KAFKA_CONTAINER" \
  kafka-topics --list \
  --bootstrap-server localhost:9092

echo ""
echo "✓ Kafka is ready for use"
