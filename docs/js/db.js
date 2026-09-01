// IndexedDB storage for folders, notebooks and pages.
// Everything lives on this device; nothing is uploaded anywhere.

const DB_NAME = 'inkwell';
const DB_VERSION = 1;
const STORES = ['folders', 'notebooks', 'pages'];

let dbPromise = null;

function openDB() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains('folders')) {
        db.createObjectStore('folders', { keyPath: 'id' });
      }
      if (!db.objectStoreNames.contains('notebooks')) {
        const store = db.createObjectStore('notebooks', { keyPath: 'id' });
        store.createIndex('folderId', 'folderId');
      }
      if (!db.objectStoreNames.contains('pages')) {
        const store = db.createObjectStore('pages', { keyPath: 'id' });
        store.createIndex('notebookId', 'notebookId');
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

function run(storeName, mode, fn) {
  return openDB().then(
    (db) =>
      new Promise((resolve, reject) => {
        const tx = db.transaction(storeName, mode);
        const req = fn(tx.objectStore(storeName));
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error);
        if (req) {
          req.onsuccess = () => resolve(req.result);
          req.onerror = () => reject(req.error);
        } else {
          tx.oncomplete = () => resolve();
        }
      })
  );
}

export const uid = () =>
  crypto.randomUUID ? crypto.randomUUID() : 'id-' + Math.random().toString(36).slice(2) + Date.now();

export const db = {
  all: (store) => run(store, 'readonly', (s) => s.getAll()),
  get: (store, id) => run(store, 'readonly', (s) => s.get(id)),
  put: (store, value) => run(store, 'readwrite', (s) => s.put(value)),
  del: (store, id) => run(store, 'readwrite', (s) => s.delete(id)),

  byIndex: (store, index, value) =>
    run(store, 'readonly', (s) => s.index(index).getAll(value)),

  async putMany(store, values) {
    const database = await openDB();
    return new Promise((resolve, reject) => {
      const tx = database.transaction(store, 'readwrite');
      const os = tx.objectStore(store);
      values.forEach((v) => os.put(v));
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  },

  async delMany(store, ids) {
    const database = await openDB();
    return new Promise((resolve, reject) => {
      const tx = database.transaction(store, 'readwrite');
      const os = tx.objectStore(store);
      ids.forEach((id) => os.delete(id));
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  },

  async clearAll() {
    const database = await openDB();
    return new Promise((resolve, reject) => {
      const tx = database.transaction(STORES, 'readwrite');
      STORES.forEach((name) => tx.objectStore(name).clear());
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  },

  async exportAll() {
    const [folders, notebooks, pages] = await Promise.all(STORES.map((s) => db.all(s)));
    return { format: 'inkwell-backup', version: 1, exportedAt: new Date().toISOString(), folders, notebooks, pages };
  },

  async importAll(data, { replace = false } = {}) {
    if (!data || data.format !== 'inkwell-backup') {
      throw new Error('That file is not an Inkwell backup.');
    }
    if (replace) await db.clearAll();
    await db.putMany('folders', data.folders || []);
    await db.putMany('notebooks', data.notebooks || []);
    await db.putMany('pages', data.pages || []);
  },
};
