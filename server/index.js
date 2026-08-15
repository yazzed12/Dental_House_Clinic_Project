const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const fs = require('fs-extra');
const path = require('path');

const app = express();
const PORT = 5000;
const DATA_FILE = path.join(__dirname, 'data', 'consultations.json');

app.use(cors());
app.use(bodyParser.json());

// Request Logging Middleware
app.use((req, res, next) => {
  console.log(`[${new Date().toLocaleTimeString()}] ${req.method} ${req.url}`);
  next();
});

// Ensure data file exists
async function ensureDataFile() {
  await fs.ensureDir(path.dirname(DATA_FILE));
  if (!(await fs.pathExists(DATA_FILE))) {
    await fs.writeJson(DATA_FILE, {});
  }
}

// GET Consultation by Patient ID
app.get('/api/consultations/:patientId', async (req, res) => {
  try {
    const { patientId } = req.params;
    const db = await fs.readJson(DATA_FILE);
    const consultation = db[patientId];
    
    if (!consultation) {
      return res.status(404).json({ message: 'No consultation found for this patient.' });
    }
    
    res.json(consultation);
  } catch (error) {
    res.status(500).json({ error: 'Failed to load consultation.' });
  }
});

// POST Save/Initialize Consultation
app.post('/api/consultations/:patientId', async (req, res) => {
  try {
    const { patientId } = req.params;
    const { toothData } = req.body;
    const db = await fs.readJson(DATA_FILE);
    
    db[patientId] = {
      patientId,
      lastUpdated: new Date().toISOString(),
      toothData: toothData || {}
    };
    
    await fs.writeJson(DATA_FILE, db, { spaces: 2 });
    res.json(db[patientId]);
  } catch (error) {
    res.status(500).json({ error: 'Failed to save consultation.' });
  }
});

// PATCH Update single tooth
app.patch('/api/consultations/:patientId/tooth/:toothId', async (req, res) => {
  try {
    const { patientId, toothId } = req.params;
    const updates = req.body;
    const db = await fs.readJson(DATA_FILE);
    
    if (!db[patientId]) {
      db[patientId] = { patientId, toothData: {} };
    }
    
    db[patientId].toothData[toothId] = {
      ...(db[patientId].toothData[toothId] || {}),
      ...updates,
      lastUpdated: new Date().toISOString()
    };
    
    db[patientId].lastUpdated = new Date().toISOString();
    
    await fs.writeJson(DATA_FILE, db, { spaces: 2 });
    res.json(db[patientId].toothData[toothId]);
  } catch (error) {
    res.status(500).json({ error: 'Failed to update tooth record.' });
  }
});

app.listen(PORT, async () => {
  await ensureDataFile();
  console.log(`Dental Clinical Backend running on http://localhost:${PORT}`);
});
