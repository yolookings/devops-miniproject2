require('dotenv').config();
const express = require('express');
const mysql = require('mysql2/promise');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

const dbConfig = {
  host: process.env.DB_HOST || 'proxysql',
  port: process.env.DB_PORT || 3306,
  user: process.env.DB_USER || 'appuser',
  password: process.env.DB_PASSWORD || 'apppassword',
  database: process.env.DB_NAME || 'ecommerce',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0
};

let pool;

async function initDB() {
  try {
    pool = mysql.createPool(dbConfig);
    const connection = await pool.getConnection();
    console.log('Database connected successfully');
    connection.release();
  } catch (error) {
    console.warn('Database not available yet:', error.message);
  }
}

app.get('/api/products', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }
    
    const [rows] = await pool.query('SELECT * FROM products LIMIT 20');
    res.json({ 
      success: true, 
      data: rows,
      message: 'Products fetched successfully (READ query)' 
    });
  } catch (error) {
    console.error('Error fetching products:', error.message);
    res.status(500).json({ error: 'Failed to fetch products' });
  }
});

app.post('/api/orders', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }
    
    const { product_id, quantity, customer_name } = req.body;
    
    if (!product_id || !quantity || !customer_name) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    
    const [result] = await pool.query(
      'INSERT INTO orders (product_id, quantity, customer_name, created_at) VALUES (?, ?, ?, NOW())',
      [product_id, quantity, customer_name]
    );
    
    res.json({ 
      success: true, 
      order_id: result.insertId,
      message: 'Order created successfully (WRITE query)' 
    });
  } catch (error) {
    console.error('Error creating order:', error.message);
    res.status(500).json({ error: 'Failed to create order' });
  }
});

app.get('/api/orders', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }
    
    const [rows] = await pool.query('SELECT * FROM orders ORDER BY created_at DESC LIMIT 20');
    res.json({ 
      success: true, 
      data: rows,
      message: 'Orders fetched successfully (READ query)' 
    });
  } catch (error) {
    console.error('Error fetching orders:', error.message);
    res.status(500).json({ error: 'Failed to fetch orders' });
  }
});

initDB().then(() => {
  app.listen(PORT, () => {
    console.log(`E-commerce application running on port ${PORT}`);
    console.log('Endpoints:');
    console.log('  GET  /health        - Health check');
    console.log('  GET  /api/products  - List products (READ)');
    console.log('  POST /api/orders    - Create order (WRITE)');
    console.log('  GET  /api/orders    - List orders (READ)');
  });
});

module.exports = app;