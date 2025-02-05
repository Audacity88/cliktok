const express = require('express');
const cors = require('cors');
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
const app = express();
const port = process.env.PORT || 3000;

// Enable CORS for all routes
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Accept', 'Origin'],
  credentials: true,
  exposedHeaders: ['Content-Type', 'Accept', 'Origin']
}));

app.use(express.json());

// Log all requests
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.url}`);
  console.log('Headers:', req.headers);
  console.log('Body:', req.body);
  console.log('Client IP:', req.ip);
  console.log('Protocol:', req.protocol);
  console.log('Secure:', req.secure);
  console.log('X-Forwarded-For:', req.get('x-forwarded-for'));
  next();
});

app.get('/config', (req, res) => {
  console.log('Received request for /config');
  console.log('Client headers:', req.headers);
  if (!process.env.STRIPE_PUBLISHABLE_KEY) {
    console.error('Missing STRIPE_PUBLISHABLE_KEY');
    return res.status(500).json({ error: 'Server configuration error' });
  }
  res.json({ publishableKey: process.env.STRIPE_PUBLISHABLE_KEY });
});

app.post('/create-payment-intent', async (req, res) => {
  try {
    const { amount, currency = 'usd' } = req.body;
    console.log('Creating payment intent:', { amount, currency });

    const paymentIntent = await stripe.paymentIntents.create({
      amount: Math.round(amount * 100),
      currency,
      automatic_payment_methods: {
        enabled: true,
      },
    });

    res.json({ clientSecret: paymentIntent.client_secret });
  } catch (error) {
    console.error('Error creating payment intent:', error);
    res.status(500).json({ error: error.message });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  const os = require('os');
  const networkInterfaces = os.networkInterfaces();
  res.json({
    status: 'ok',
    interfaces: networkInterfaces,
    timestamp: new Date().toISOString()
  });
});

// Create server with IPv4 configuration
app.listen(port, '127.0.0.1', () => {
  const os = require('os');
  const networkInterfaces = os.networkInterfaces();
  console.log('Network interfaces:', networkInterfaces);
  console.log(`Server running on http://127.0.0.1:${port}`);
  
  // Print all available interfaces
  Object.keys(networkInterfaces).forEach((ifname) => {
    networkInterfaces[ifname].forEach((iface) => {
      console.log(`Interface ${ifname}: ${iface.family} - ${iface.address}`);
    });
  });
});

// Handle errors
app.on('error', (error) => {
  console.error('Server error:', error);
  if (error.syscall !== 'listen') {
    throw error;
  }

  switch (error.code) {
    case 'EACCES':
      console.error(`Port ${port} requires elevated privileges`);
      process.exit(1);
      break;
    case 'EADDRINUSE':
      console.error(`Port ${port} is already in use`);
      process.exit(1);
      break;
    default:
      throw error;
  }
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('Received SIGTERM. Performing graceful shutdown...');
  app.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});
