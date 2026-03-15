const express = require('express');
const client = require('prom-client');
const KafkaProducer = require('./kafka-producer');

const app = express();
const port = process.env.PORT || 3000;
const tenantName = process.env.TENANT_NAME || 'default';
const domain = process.env.DOMAIN || 'default.example.com';
const kafkaBroker = process.env.KAFKA_BROKER || 'localhost:9092';

// Prometheus metrics
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.1, 0.5, 1, 2, 5]
});

// Middleware: track request duration
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration
      .labels(req.method, req.route?.path || req.path, res.statusCode)
      .observe(duration);
  });
  next();
});

// Health check endpoint (for liveness/readiness probes)
app.get('/health', (req, res) => {
  res.json({ status: 'ok', tenant: tenantName, domain });
});

// Metrics endpoint (for Prometheus scraping)
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

// Home endpoint
app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>${tenantName}</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 50px; background: #f5f5f5; }
        .container { background: white; padding: 20px; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        .info { background: #e3f2fd; padding: 10px; border-radius: 3px; margin: 10px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>Welcome to ${tenantName}</h1>
        <div class="info">
          <p><strong>Tenant:</strong> ${tenantName}</p>
          <p><strong>Domain:</strong> ${domain}</p>
          <p><strong>Version1:</strong> ${process.env.VERSION || 'dev'}</p>
        </div>
        <p>This is a multi-tenant website running on Kubernetes.</p>
      </div>
    </body>
    </html>
  `);
});

// Initialize Kafka producer and start server
async function start() {
  const producer = new KafkaProducer(kafkaBroker);

  try {
    await producer.connect();
    console.log(`[${tenantName}] Connected to Kafka at ${kafkaBroker}`);

    // Publish WebsiteCreated event
    const event = {
      event: 'WebsiteCreated',
      tenant: tenantName,
      domain: domain,
      timestamp: new Date().toISOString(),
      version: process.env.VERSION || 'dev'
    };

    await producer.publishEvent(event);
    console.log(`[${tenantName}] Published event:`, event);

  } catch (err) {
    console.warn(`[${tenantName}] Kafka error (non-fatal): ${err.message}`);
  }

  // Start HTTP server regardless of Kafka status
  app.listen(port, () => {
    console.log(`[${tenantName}] Website server listening on port ${port}`);
  });

  // Graceful shutdown
  process.on('SIGTERM', async () => {
    console.log(`[${tenantName}] SIGTERM received, gracefully shutting down...`);
    await producer.disconnect();
    process.exit(0);
  });
}

start();
