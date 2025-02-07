const express = require('express');
const cors = require('cors');
require('dotenv').config();

// Validate required environment variables
const requiredEnvVars = ['STRIPE_SECRET_KEY', 'STRIPE_PUBLISHABLE_KEY'];
const missingEnvVars = requiredEnvVars.filter(envVar => !process.env[envVar]);

if (missingEnvVars.length > 0) {
  console.error('Missing required environment variables:', missingEnvVars.join(', '));
  process.exit(1);
}

const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
const app = express();
const port = process.env.PORT || 3000;

// Enable CORS for all routes
app.use(cors({
  origin: process.env.NODE_ENV === 'production' 
    ? ['https://cliktok.com', 'capacitor://localhost', 'http://localhost'] 
    : '*',
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Accept', 'Origin'],
  credentials: true,
  exposedHeaders: ['Content-Type', 'Accept', 'Origin']
}));

app.use(express.json());

// Log all requests
app.use((req, res, next) => {
  const mode = process.env.NODE_ENV || 'development';
  console.log(`[${mode.toUpperCase()}] ${new Date().toISOString()} - ${req.method} ${req.path}`);
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
  if (!process.env.STRIPE_PUBLISHABLE_KEY) {
    console.error('Missing STRIPE_PUBLISHABLE_KEY');
    return res.status(500).json({ error: 'Server configuration error' });
  }
  
  const mode = process.env.NODE_ENV || 'development';
  res.json({ 
    publishableKey: process.env.STRIPE_PUBLISHABLE_KEY,
    mode: mode,
    isTestMode: mode === 'test'
  });
});

app.post('/create-payment-intent', async (req, res) => {
  try {
    const { amount, currency = 'usd' } = req.body;
    const mode = process.env.NODE_ENV || 'development';
    console.log(`Creating payment intent [${mode}]:`, { amount, currency });

    const paymentIntent = await stripe.paymentIntents.create({
      amount: amount, // Amount should already be in cents from client
      currency,
      automatic_payment_methods: {
        enabled: true,
      },
      metadata: {
        mode: mode
      }
    });

    res.json({ 
      clientSecret: paymentIntent.client_secret,
      mode: mode,
      isTestMode: mode === 'test'
    });
  } catch (error) {
    console.error('Error creating payment intent:', error);
    res.status(500).json({ error: error.message });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  const mode = process.env.NODE_ENV || 'development';
  res.json({ 
    status: 'ok',
    timestamp: new Date().toISOString(),
    mode: mode,
    stripe: 'configured'
  });
});

// Create server with IPv4 configuration
app.listen(port, '127.0.0.1', () => {
  const mode = process.env.NODE_ENV || 'development';
  console.log(`Server running in ${mode.toUpperCase()} mode on http://127.0.0.1:${port}`);
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
