import dotenv from 'dotenv';
dotenv.config();

import express from 'express';
import cors from 'cors';
import { pexelsRouter } from './routes/pexels';

const app = express();
const port = process.env.PORT || 4000;

// Middleware
app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'autoslate-backend' });
});

// Routes
app.use('/api/stock/pexels', pexelsRouter);

// Start server
app.listen(port, () => {
  console.log(`AutoSlate backend listening on port ${port}`);
  
  // Check if Pexels API key is configured
  if (!process.env.PEXELS_API_KEY) {
    console.warn('⚠️  WARNING: PEXELS_API_KEY is not configured in .env file');
    console.warn('   Pexels API endpoints will return errors until the key is set');
  } else {
    console.log('✓ Pexels API key configured');
  }
});

