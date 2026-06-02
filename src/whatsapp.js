const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode');
const qrcodeTerminal = require('qrcode-terminal');

class WhatsAppService {
  constructor() {
    this.client = null;
    this.qrCodeBase64 = null;
    this.status = 'disconnected';
    this.ready = false;
    this.onMessage = null;
  }

  async initialize() {
    if (this.client) return;

    const puppeteerOpts = {
      headless: true,
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-accelerated-2d-canvas',
        '--no-first-run',
        '--no-zygote',
        '--single-process',
        '--disable-gpu'
      ]
    };

    const chromiumPath = process.env.CHROMIUM_PATH || '';
    if (chromiumPath) {
      puppeteerOpts.executablePath = chromiumPath;
    }

    this.client = new Client({
      authStrategy: new LocalAuth({ dataPath: './.wwebjs_auth' }),
      puppeteer: puppeteerOpts
    });

    this.client.on('qr', async (qr) => {
      try {
        this.qrCodeBase64 = await qrcode.toDataURL(qr, { width: 300, margin: 2 });
      } catch {
        this.qrCodeBase64 = null;
      }
      this.status = 'connecting';
      console.log('\n[WhatsApp] ============================================');
      console.log('[WhatsApp]  Escaneie o QR Code abaixo com o WhatsApp');
      console.log('[WhatsApp]  (WhatsApp > Aparelhos conectados > Conectar)');
      console.log('[WhatsApp] ============================================\n');
      qrcodeTerminal.generate(qr, { small: true });
      console.log('\n[WhatsApp] QR Code também disponível na página de Configurações.\n');
    });

    this.client.on('ready', () => {
      this.status = 'connected';
      this.ready = true;
      this.qrCodeBase64 = null;
      console.log('[WhatsApp] Conectado!');
    });

    this.client.on('authenticated', () => {
      console.log('[WhatsApp] Autenticado.');
    });

    this.client.on('auth_failure', (msg) => {
      console.error('[WhatsApp] Falha na autenticação:', msg);
      this.status = 'error';
    });

    this.client.on('disconnected', (reason) => {
      console.log('[WhatsApp] Desconectado:', reason);
      this.status = 'disconnected';
      this.ready = false;
      this.qrCodeBase64 = null;
    });

    this.client.on('message', async (msg) => {
      if (msg.fromMe || !msg.body) return;
      if (this.onMessage) {
        this.onMessage({
          from: msg.from.replace('@c.us', ''),
          body: msg.body,
          name: msg._data?.notifyName || msg._data?.pushname || 'Desconhecido',
          timestamp: msg.timestamp
        });
      }
    });

    try {
      await this.client.initialize();
    } catch (err) {
      console.error('[WhatsApp] Erro ao inicializar:', err.message);
      this.status = 'error';
    }
  }

  async reconnect() {
    await this.logout();
    await this.initialize();
  }

  getStatus() {
    return { status: this.status, ready: this.ready, hasQrCode: !!this.qrCodeBase64 };
  }

  getQrCode() {
    return this.qrCodeBase64;
  }

  async sendMessage(to, message) {
    if (!this.ready) throw new Error('WhatsApp não está conectado');
    const chatId = to.includes('@c.us') ? to : `${to}@c.us`;
    await this.client.sendMessage(chatId, message);
  }

  async logout() {
    if (this.client) {
      try { await this.client.logout(); } catch {}
      try { await this.client.destroy(); } catch {}
      this.client = null;
    }
    this.ready = false;
    this.status = 'disconnected';
    this.qrCodeBase64 = null;
  }
}

const wpp = new WhatsAppService();
module.exports = wpp;
