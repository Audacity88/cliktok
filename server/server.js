const express = require('express');
const cors = require('cors');
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env.local') });

// Validate required environment variables
const requiredEnvVars = ['STRIPE_SECRET_KEY', 'STRIPE_PUBLISHABLE_KEY'];
const missingEnvVars = requiredEnvVars.filter(envVar => !process.env[envVar]);

if (missingEnvVars.length > 0) {
  console.error('Missing required environment variables:', missingEnvVars.join(', '));
  process.exit(1);
}

// Initialize Stripe with the secret key from environment variables
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY, {
    apiVersion: '2023-10-16', // Use stable API version
    appInfo: {
        name: 'ClicTok',
        version: '1.0.0'
    }
});
const app = express();
const port = process.env.PORT || 3000;

// Enable CORS for all routes with specific configuration
app.use(cors({
    origin: '*', // Allow all origins in development
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Accept', 'Authorization'],
    credentials: true,
    preflightContinue: true,
    optionsSuccessStatus: 204
}));

// Add OPTIONS handler for preflight requests
app.options('*', cors());

app.use(express.json());

// Log all requests
app.use((req, res, next) => {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
    console.log('Headers:', req.headers);
    console.log('Body:', req.body);
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

        if (!amount || amount < 1) {
            return res.status(400).json({ error: 'Invalid amount' });
        }

        console.log(`Creating payment intent for amount: ${amount} ${currency}`);

        // Create the payment intent
        const paymentIntent = await stripe.paymentIntents.create({
            amount: amount, 
            currency: currency,
            payment_method_types: ['card'],
        });

        console.log('--- Payment Intent Details ---');
        console.log('ID:', paymentIntent.id); 
        console.log('Client Secret:', paymentIntent.client_secret);
        console.log('Amount:', paymentIntent.amount);
        console.log('Currency:', paymentIntent.currency);
        console.log('Status:', paymentIntent.status);
        console.log('Capture Method:', paymentIntent.capture_method);
        console.log('Confirmation Method:', paymentIntent.confirmation_method);
        console.log('Created:', paymentIntent.created);
        console.log('Livemode:', paymentIntent.livemode);
        console.log('Payment Method Types:', paymentIntent.payment_method_types);
        console.log('-------------------------------');

        res.json({
            paymentIntentId: paymentIntent.id,
            clientSecret: paymentIntent.client_secret,
            publishableKey: process.env.STRIPE_PUBLISHABLE_KEY
        });
    } catch (error) {
        console.error('Error creating payment intent:', error);
        res.status(500).json({ 
            error: error.message
        });
    }
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ 
        status: 'ok',
        timestamp: new Date().toISOString(),
        mode: process.env.NODE_ENV || 'development'
    });
});

// Add after the other app.get routes

app.get('/server-info', (req, res) => {
    const { networkInterfaces } = require('os');
    const nets = networkInterfaces();
    const addresses = [];

    // Collect all IPv4 addresses
    for (const name of Object.keys(nets)) {
        for (const net of nets[name]) {
            // Skip internal and non-IPv4 addresses
            if (net.family === 'IPv4' && !net.internal) {
                addresses.push({
                    interface: name,
                    address: net.address,
                    url: `http://${net.address}:${port}`
                });
            }
        }
    }

    res.json({
        addresses,
        port,
        mode: process.env.NODE_ENV || 'development'
    });
});

// Start server
const server = app.listen(port, '0.0.0.0', () => {
    const { networkInterfaces } = require('os');
    const nets = networkInterfaces();
    
    console.log('\n=== Server Started ===');
    console.log('Time:', new Date().toISOString());
    console.log('Environment:', process.env.NODE_ENV || 'development');
    console.log('\nListening on all network interfaces:');
    console.log(`Port: ${port}`);
    
    // Log all available interfaces and their addresses
    for (const name of Object.keys(nets)) {
        for (const net of nets[name]) {
            if (net.family === 'IPv4') {
                console.log(`\nInterface: ${name}`);
                console.log(`  Address: ${net.address}`);
                console.log(`  URL: http://${net.address}:${port}`);
                console.log(`  Internal: ${net.internal}`);
                console.log(`  CIDR: ${net.cidr}`);
            }
        }
    }
    
    console.log('\nServer is ready to accept connections from any interface');
});

// Increase the timeout values
server.keepAliveTimeout = 61000;
server.headersTimeout = 62000;

// Add request timeout middleware with longer timeout
app.use((req, res, next) => {
    res.setTimeout(30000, () => {
        console.log('Request has timed out.');
        res.status(408).send('Request has timed out');
    });
    next();
});

// Add detailed error logging
app.use((err, req, res, next) => {
    console.error('\nError occurred:', new Date().toISOString());
    console.error('  Message:', err.message);
    console.error('  Stack:', err.stack);
    console.error('  Request URL:', req.url);
    console.error('  Request method:', req.method);
    console.error('  Request headers:', req.headers);
    console.error('  Request body:', req.body);
    console.error('  Client IP:', req.ip);
    
    res.status(500).json({ 
        error: err.message,
        code: err.code || 'INTERNAL_ERROR'
    });
});

// Add detailed connection logging
app.use((req, res, next) => {
    const start = Date.now();
    console.log(`\n=== Incoming Request ===`);
    console.log('Time:', new Date().toISOString());
    console.log('URL:', req.url);
    console.log('Method:', req.method);
    console.log('Client IP:', req.ip);
    console.log('Headers:', JSON.stringify(req.headers, null, 2));
    if (req.body && Object.keys(req.body).length > 0) {
        console.log('Body:', JSON.stringify(req.body, null, 2));
    }
    
    res.on('finish', () => {
        const duration = Date.now() - start;
        console.log(`\n=== Request Completed ===`);
        console.log('Time:', new Date().toISOString());
        console.log('Duration:', duration + 'ms');
        console.log('Status:', res.statusCode);
        console.log('Headers:', JSON.stringify(res.getHeaders(), null, 2));
    });
    
    next();
});

// Handle server errors
server.on('error', (error) => {
    console.error('\n=== Server Error ===');
    console.error('Time:', new Date().toISOString());
    console.error('Error:', error);
    
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
    console.log('\n=== Graceful Shutdown ===');
    console.log('Time:', new Date().toISOString());
    console.log('Closing server...');
    
    server.close(() => {
        console.log('Server closed');
        process.exit(0);
    });
});
