const express = require('express');
const { Pool } = require('pg');
 
const app = express();
const PORT = process.env.PORT || 3000;
 
// Read DB config from environment — NEVER hardcode credentials
const pool = new Pool({
  host:     process.env.DB_HOST     || 'postgres',
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME     || 'appdb',
  user:     process.env.DB_USER     || 'appuser',
  password: process.env.DB_PASSWORD,
  // Connection pooling — critical for production
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});
  
app.use(express.json());
 
// Health endpoint — required for Docker HEALTHCHECK and load balancers
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'node-api' });
});
 
// DB connectivity check
app.get('/db-health', async (req, res) => {
  try {
    const client = await pool.connect();
    const result = await client.query('SELECT NOW()');
    client.release();
    res.json({ status: 'ok', db_time: result.rows[0].now });
  } catch (err) {
    res.status(503).json({ status: 'error', message: err.message });
  }
});
 
// Graceful shutdown — handle SIGTERM from Docker
process.on('SIGTERM', async () => {
  console.log('SIGTERM received. Draining connections...');
  await pool.end();
  process.exit(0);
});
 
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Node API listening on port ${PORT}`);
});
