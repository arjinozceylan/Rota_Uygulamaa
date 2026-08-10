const express = require("express");
const cors = require("cors");
const Database = require("better-sqlite3");
const path = require("path");
const fs = require("fs");

const app = express();
const PORT = 3100;

// Sunucu sadece 127.0.0.1'de dinliyor (asagida) ama varsayilan cors()
// her origin'e izin veriyordu — ayni bilgisayarda acik kotu niyetli bir
// web sayfasi bu adrese fetch atip hasta listesini (ad/telefon/adres)
// kimlik dogrulamasi olmadan okuyabilirdi. Sadece localhost/127.0.0.1
// origin'lerine izin verilir (web uygulamasi da bu makinede calisir).
app.use(cors({
  origin: function (origin, callback) {
    if (!origin) return callback(null, true);
    if (/^https?:\/\/localhost(:\d+)?$/.test(origin)) return callback(null, true);
    if (/^https?:\/\/127\.0\.0\.1(:\d+)?$/.test(origin)) return callback(null, true);
    return callback(new Error("CORS engellendi: " + origin));
  },
}));
app.use(express.json({ limit: "10mb" }));

// Veritabanını kullanıcı verisinin güvenli tutulacağı local klasörde sakla.
const dataDir = path.join(__dirname, "data");

if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

const dbPath = path.join(dataDir, "rota360.db");
const db = new Database(dbPath);

// Hasta/adres havuzu
db.exec(`
  CREATE TABLE IF NOT EXISTS patients (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    external_code TEXT,
    patient_name TEXT,
    address TEXT NOT NULL,
    district TEXT,
    city TEXT,
    phone TEXT,
    latitude REAL,
    longitude REAL,
    notes TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
  )
`);

// Adres → koordinat cache'i.
// Aynı adres sonraki haftalarda tekrar gelirse yeniden geocode edilmez.
db.exec(`
  CREATE TABLE IF NOT EXISTS geocode_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    address TEXT NOT NULL UNIQUE,
    latitude REAL,
    longitude REAL,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
  )
`);

// Excel/CSV yükleme geçmişi
db.exec(`
  CREATE TABLE IF NOT EXISTS imports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_name TEXT NOT NULL,
    imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_count INTEGER NOT NULL DEFAULT 0
  )
`);

app.get("/", (req, res) => {
  res.json({
    message: "Rota360 local backend çalışıyor",
    database: dbPath,
  });
});

app.get("/health", (req, res) => {
  res.json({
    ok: true,
    service: "rota360-local-backend",
  });
});

app.get("/patients", (req, res) => {
  const rows = db
    .prepare(`
      SELECT *
      FROM patients
      WHERE is_active = 1
      ORDER BY id DESC
    `)
    .all();

  res.json(rows);
});

// Daha önce geocode edilmiş bir adresin koordinatlarını getir
app.get("/geocode-cache", (req, res) => {
  try {
    const address = req.query.address;

    if (!address) {
      return res.status(400).json({
        error: "address zorunlu",
      });
    }

    const row = db
      .prepare(`
        SELECT address, latitude, longitude
        FROM geocode_cache
        WHERE address = ?
      `)
      .get(address);

    if (!row) {
      return res.status(404).json({
        found: false,
      });
    }

    res.json({
      found: true,
      ...row,
    });
  } catch (error) {
    console.error("Geocode cache read error:", error);
    res.status(500).json({
      error: "Geocode cache okunamadı",
    });
  }
});


// Birden fazla adresin cache durumunu tek istekte kontrol et
app.post("/geocode-cache/bulk", (req, res) => {
  try {
    const { addresses } = req.body;

    if (!Array.isArray(addresses)) {
      return res.status(400).json({
        error: "addresses zorunlu",
      });
    }

    const findAddress = db.prepare(`
      SELECT address, latitude, longitude
      FROM geocode_cache
      WHERE address = ?
    `);

    const results = {};

    for (const address of addresses) {
      if (!address) continue;

      const row = findAddress.get(address);

      if (row) {
        results[address] = {
          latitude: row.latitude,
          longitude: row.longitude,
        };
      }
    }

    res.json({
      found: Object.keys(results).length,
      results,
    });
  } catch (error) {
    console.error("Bulk geocode cache error:", error);

    res.status(500).json({
      error: "Geocode cache toplu okunamadı",
    });
  }
});

// Yeni geocode sonucunu lokal cache'e kaydet
app.post("/geocode-cache", (req, res) => {
  try {
    const { address, latitude, longitude } = req.body;

    if (!address) {
      return res.status(400).json({
        error: "address zorunlu",
      });
    }

    db.prepare(`
      INSERT INTO geocode_cache (
        address,
        latitude,
        longitude
      )
      VALUES (?, ?, ?)
      ON CONFLICT(address)
      DO UPDATE SET
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        updated_at = CURRENT_TIMESTAMP
    `).run(
      address,
      latitude ?? null,
      longitude ?? null
    );

    res.json({
      ok: true,
    });
  } catch (error) {
    console.error("Geocode cache write error:", error);
    res.status(500).json({
      error: "Geocode cache kaydedilemedi",
    });
  }
});

// Haftalık CSV/Excel importundan gelen hasta-adres havuzunu
// tamamen lokal SQLite'a kaydeder.
// Yeni haftalık dosya geldiğinde eski aktif havuzun yerini alır.
app.post("/patients/import", (req, res) => {
  const { fileName, patients } = req.body;

  if (!fileName || !Array.isArray(patients)) {
    return res.status(400).json({
      error: "fileName ve patients zorunlu",
    });
  }

  const replacePatients = db.transaction(() => {
    // Haftalık yeni liste geldiğinde eski aktif kayıtları pasif yap.
    db.prepare(`
      UPDATE patients
      SET is_active = 0,
          updated_at = CURRENT_TIMESTAMP
      WHERE is_active = 1
    `).run();

    const insertPatient = db.prepare(`
      INSERT INTO patients (
        external_code,
        patient_name,
        address,
        district,
        city,
        phone,
        latitude,
        longitude,
        notes,
        is_active
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
    `);

    let inserted = 0;

    for (const patient of patients) {
      if (!patient || !patient.address) continue;

      insertPatient.run(
        patient.externalCode ?? null,
        patient.patientName ?? null,
        patient.address,
        patient.district ?? null,
        patient.city ?? null,
        patient.phone ?? null,
        patient.latitude ?? null,
        patient.longitude ?? null,
        patient.notes ?? null
      );

      inserted++;
    }

    db.prepare(`
      INSERT INTO imports (
        file_name,
        row_count
      )
      VALUES (?, ?)
    `).run(fileName, inserted);

    return inserted;
  });

  try {
    const inserted = replacePatients();

    res.status(201).json({
      message: "Hasta/adres listesi lokal veritabanına aktarıldı",
      inserted,
    });
  } catch (error) {
    console.error("Local import error:", error);

    res.status(500).json({
      error: "Lokal veritabanına aktarım başarısız",
    });
  }
});

// Excel/CSV yükleme geçmişini getir
app.get("/imports", (req, res) => {
  try {
    const rows = db
      .prepare(`
        SELECT *
        FROM imports
        ORDER BY imported_at DESC
      `)
      .all();

    res.json(rows);
  } catch (error) {
    console.error("Import history error:", error);
    res.status(500).json({ error: "Yükleme geçmişi okunamadı" });
  }
});

app.listen(PORT, "127.0.0.1", () => {
  console.log(`Rota360 local backend http://127.0.0.1:${PORT} adresinde çalışıyor`);
  console.log(`SQLite database: ${dbPath}`);
});