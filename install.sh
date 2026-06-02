#!/bin/sh
set -eu

# ==============================================================
# Script de instalação — ERP WhatsApp
# Uso: sudo bash install.sh          (instalar)
#       sudo bash install.sh uninstall (desinstalar)
#
# Chatbot WhatsApp integrado ao ERP Fiscal
# ==============================================================

INSTALL_DIR="/var/www/erpwhatsapp"
SRC_DIR="$INSTALL_DIR/src"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_CONF="$NGINX_AVAILABLE/default"
BACKUP_ROOT="/var/backups/erpwhatsapp"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2; }
error() { printf "${RED}[ERRO]${NC} %s\n" "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || error "Execute como root: sudo bash install.sh"

if [ -n "${SUDO_USER:-}" ]; then
  PM2_USER="$SUDO_USER"
else
  PM2_USER="root"
fi
PM2_AS_USER=""
[ "$PM2_USER" != "root" ] && PM2_AS_USER="sudo -u $PM2_USER"

uninstall_app() {
  [ -f "$INSTALL_DIR/.env" ] || error ".env não encontrado"
  local upm2="erpwhatsapp"
  upm2=$(grep -oP '^PM2_APP_NAME=\K.*' "$INSTALL_DIR/.env" 2>/dev/null || echo "erpwhatsapp")
  info "Parando PM2 ($upm2)"
  $PM2_AS_USER pm2 delete "$upm2" 2>/dev/null || true
  $PM2_AS_USER pm2 save --force 2>/dev/null || true
  info "Removendo $INSTALL_DIR"
  rm -rf "$INSTALL_DIR"
  info "Desinstalação concluída!"
}

case "${1:-}" in
  uninstall) uninstall_app; exit 0 ;;
esac

ROLLBACK_DIR=""
cleanup_on_error() {
  local rc=$?; [ $rc -eq 0 ] && return 0
  warn "ERRO — revertendo..."; rm -rf "$INSTALL_DIR" 2>/dev/null || true
  $PM2_AS_USER pm2 delete "$PM2_APP_NAME" 2>/dev/null || true; exit $rc
}
trap 'cleanup_on_error' EXIT
trap 'error "Interrompido"' INT TERM

command -v node >/dev/null 2>&1 || error "Node.js não encontrado"
command -v npm  >/dev/null 2>&1 || error "npm não encontrado"

mkdir -p "$SRC_DIR" "$INSTALL_DIR/backups"

echo ""
echo "============================================"
echo "  Configuração ERP WhatsApp"
echo "============================================"

_check_port() {
  local p=$1
  if command -v ss >/dev/null 2>&1; then
    ss -tlnp "sport = :$p" 2>/dev/null | grep -qv 'State.*Recv-Q' && return 0
  elif command -v lsof >/dev/null 2>&1; then
    lsof -i:"$p" 2>/dev/null | grep -q LISTEN && return 0
  fi
  return 1
}

while :; do
  printf "Porta do app [3004]: "; read -r APP_PORT
  APP_PORT=${APP_PORT:-3004}
  if _check_port "$APP_PORT"; then
    warn "Porta $APP_PORT em uso!"; printf "  (M)atar, (T)rocar, (C)ancelar [M/t/c]: "; read -r PORT_ACT
    case "$PORT_ACT" in [Tt]) continue ;; [Cc]) error "Cancelado" ;; *) fuser -k "$APP_PORT/tcp" 2>/dev/null; sleep 1 ;; esac
  fi
  break
done

printf "Nome do banco PostgreSQL [erpwhatsapp_db]: "; read -r DB_NAME
DB_NAME=${DB_NAME:-erpwhatsapp_db}
printf "Nome do app PM2 [erpwhatsapp]: "; read -r PM2_APP_NAME
PM2_APP_NAME=${PM2_APP_NAME:-erpwhatsapp}
printf "Email do admin: "; read -r ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@erpwhatsapp.com.br}
printf "Nome do admin [$ADMIN_EMAIL]: "; read -r ADMIN_NOME
ADMIN_NOME=${ADMIN_NOME:-$ADMIN_EMAIL}
printf "Senha do admin [@admin123]: "; stty -echo; read -r ADMIN_PASS; stty echo; echo ""
ADMIN_PASS=${ADMIN_PASS:-@admin123}
DB_USER=postgres; DB_PASS=wander; DB_HOST=localhost; DB_PORT=5432
APP_DOMAIN=api.projetosdinamicos.com.br
APP_LOCATION=/$PM2_APP_NAME/

info "Criando .env"
cat > "$INSTALL_DIR/.env" <<ENVEOF
PORT=$APP_PORT
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
PM2_APP_NAME=$PM2_APP_NAME
APP_DOMAIN=$APP_DOMAIN
APP_LOCATION=$APP_LOCATION
NGINX_BKP=
PASSWORD=$DB_PASS
ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_NOME=$ADMIN_NOME
ADMIN_PASS=$ADMIN_PASS
CHROMIUM_PATH=$CHROMIUM_PATH
ENVEOF
chmod 600 "$INSTALL_DIR/.env"; chown "$PM2_USER" "$INSTALL_DIR/.env"

info "Instalando dependências do sistema para Chromium/Puppeteer..."
if command -v apt-get >/dev/null 2>&1; then
  apt-get install -y chromium chromium-common chromium-sandbox ca-certificates fonts-liberation libasound2 libatk-bridge2.0-0 libatk1.0-0 libcups2 libdrm2 libgbm1 libnss3 libxcomposite1 libxdamage1 libxrandr2 xdg-utils 2>/dev/null || true
elif command -v yum >/dev/null 2>&1; then
  yum install -y chromium nss libXcomposite libXdamage libXrandr libgbm libdrm 2>/dev/null || true
fi
CHROMIUM_PATH=""
for _p in /usr/bin/chromium /usr/bin/chromium-browser /snap/bin/chromium; do
  [ -x "$_p" ] && CHROMIUM_PATH="$_p" && break
done

info "Criando package.json"
cat > "$INSTALL_DIR/package.json" <<'JSONEOF'
{
  "name": "erpwhatsapp-api",
  "version": "1.0.0",
  "private": true,
  "scripts": { "start": "node src/server.js", "dev": "node --watch src/server.js" },
  "dependencies": {
    "dotenv": "^16.4.5",
    "express": "^4.21.0",
    "pg": "^8.12.0",
    "whatsapp-web.js": "^1.25.0",
    "qrcode": "^1.5.4",
    "qrcode-terminal": "^0.12.0"
  }
}
JSONEOF

# ==============================================================
# server.js
# ==============================================================
info "Criando src/server.js"
cat > "$SRC_DIR/server.js" <<'SVREOF'
const { Pool } = require('pg');
const express = require('express');
const path = require('path');
const crypto = require('crypto');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const app = express();
const PORT = process.env.PORT || 3000;

const pool = new Pool({
    host: process.env.DB_HOST, port: process.env.DB_PORT,
    database: process.env.DB_NAME, user: process.env.DB_USER,
    password: process.env.PASSWORD
});
pool.on('error', (err) => console.error('DB Error:', err));

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

app.use((req, res, next) => {
    const origin = req.headers.origin;
    const allowed = ['https://www.projetosdinamicos.com.br','https://api.projetosdinamicos.com.br','https://erp.projetosdinamicos.com.br'];
    if (origin) {
        const m = allowed.find(o => origin === o || origin.endsWith('://' + o.split('://')[1]));
        if (m) res.header('Access-Control-Allow-Origin', m);
    }
    res.header('Access-Control-Allow-Methods','GET,POST,PUT,DELETE,OPTIONS');
    res.header('Access-Control-Allow-Headers','Content-Type, Authorization');
    if (req.method === 'OPTIONS') return res.sendStatus(200);
    next();
});

// Health
app.get('/', (req, res) => res.json({ message:'ERP WhatsApp API', status:'OK', version:'1.0.0' }));
app.get('/health', async (req, res) => {
    try { await pool.query('SELECT 1'); res.json({ status:'healthy', database:'connected' }); }
    catch(e) { res.json({ status:'unhealthy', database:'disconnected', error: e.message }); }
});

// Auth
app.post('/auth/login', async (req, res) => {
    const { nome, email, senha } = req.body;
    if ((!nome && !email) || !senha) return res.status(400).json({ error:'Credenciais obrigatórias' });
    try {
        const r = await pool.query(
            nome ? 'SELECT id,nome,email,tipo FROM usuarios WHERE nome=$1 AND senha=$2' : 'SELECT id,nome,email,tipo FROM usuarios WHERE email=$1 AND senha=$2',
            [nome || email, senha]
        );
        if (r.rows.length === 0) return res.status(401).json({ error:'Credenciais inválidas' });
        const u = r.rows[0];
        const token = crypto.createHash('sha256').update(u.email+Date.now()+'erpwhatsapp_secret').digest('hex');
        res.json({ success:true, token, usuario: u });
    } catch(e) { res.status(500).json({ error: e.message }); }
});

// Settings
app.get('/settings', async (req, res) => {
    try { const r = await pool.query('SELECT chave,valor FROM settings'); const s={}; r.rows.forEach(x=>{s[x.chave]=x.valor;}); res.json(s); }
    catch(e) { res.status(500).json({ error: e.message }); }
});
app.post('/settings', async (req, res) => {
    try { for(const k of Object.keys(req.body)) { await pool.query('INSERT INTO settings(chave,valor) VALUES($1,$2) ON CONFLICT(chave) DO UPDATE SET valor=$2',[k,req.body[k]]); } res.json({success:true}); }
    catch(e) { res.status(500).json({ error: e.message }); }
});

// ===================== WEBHOOK WHATSAPP =====================
// Endpoint que recebe mensagens do WhatsApp
app.post('/webhook', async (req, res) => {
    try {
        const { from, to, message, name, number } = req.body;
        const telefone = number || from || '';
        const nome = name || 'Desconhecido';
        const texto = message || '';

        if (!telefone || !texto) return res.json({ status: 'ignored' });

        // Busca ou cria contato
        let contato = await pool.query('SELECT * FROM contatos WHERE telefone=$1', [telefone]);
        if (contato.rows.length === 0) {
            contato = await pool.query('INSERT INTO contatos(nome,telefone,origem) VALUES($1,$2,$3) RETURNING *', [nome, telefone, 'whatsapp']);
        }
        const contatoId = contato.rows[0].id;

        // Busca ou cria conversa
        let conv = await pool.query('SELECT * FROM conversas WHERE contato_id=$1 AND status!=\'fechada\' ORDER BY id DESC LIMIT 1', [contatoId]);
        let conversaId;
        if (conv.rows.length === 0) {
            conv = await pool.query('INSERT INTO conversas(contato_id,contato_nome,contato_telefone) VALUES($1,$2,$3) RETURNING *', [contatoId, nome, telefone]);
            conversaId = conv.rows[0].id;
        } else {
            conversaId = conv.rows[0].id;
            await pool.query('UPDATE conversas SET contato_nome=$1,ultima_atividade=NOW() WHERE id=$2', [nome, conversaId]);
        }

        // Salva mensagem recebida
        await pool.query('INSERT INTO mensagens(conversa_id,texto,direcao,origem,contato_id) VALUES($1,$2,$3,$4,$5)', [conversaId, texto, 'recebida', 'contato', contatoId]);

        // Atualiza contagem de não lidas
        await pool.query('UPDATE conversas SET nao_lidas=nao_lidas+1,ultima_mensagem=$1,ultima_atividade=NOW() WHERE id=$2', [texto, conversaId]);

        // ===== AUTOMAÇÃO: verifica regras =====
        const botAtivo = await pool.query("SELECT valor FROM settings WHERE chave='bot_ativo'");
        if (botAtivo.rows.length === 0 || botAtivo.rows[0].valor !== 'false') {
            const regras = await pool.query("SELECT * FROM automacoes WHERE ativo='Sim' OR ativo='true' ORDER BY prioridade ASC");
            let resposta = null;
            for (const regra of regras.rows) {
                const gatilho = (regra.gatilho || '').toLowerCase();
                const textoLower = texto.toLowerCase();
                if (gatilho && textoLower.indexOf(gatilho) !== -1) {
                    if (regra.resposta) {
                        resposta = regra.resposta.replace(/\{\{nome\}\}/g, nome).replace(/\{\{telefone\}\}/g, telefone);
                    } else if (regra.modelo_id) {
                        const modelo = await pool.query('SELECT * FROM modelos WHERE id=$1', [regra.modelo_id]);
                        if (modelo.rows.length > 0) {
                            resposta = modelo.rows[0].conteudo.replace(/\{\{nome\}\}/g, nome);
                        }
                    }
                    if (resposta) break;
                }
            }

            // Se não achou regra, tenta saudação padrão
            if (!resposta) {
                const saudacoes = ['olá','oi','bom dia','boa tarde','boa noite','hey','ola'];
                const textoLower = texto.toLowerCase();
                if (saudacoes.some(s => textoLower.indexOf(s) !== -1)) {
                    const msgBoasVindas = await pool.query("SELECT valor FROM settings WHERE chave='msg_boasvindas'");
                    if (msgBoasVindas.rows.length > 0) {
                        resposta = msgBoasVindas.rows[0].valor.replace(/\{\{nome\}\}/g, nome);
                    }
                }
            }

            if (resposta) {
                await pool.query('INSERT INTO mensagens(conversa_id,texto,direcao,origem) VALUES($1,$2,$3,$4)', [conversaId, resposta, 'enviada', 'bot']);
                await pool.query('UPDATE conversas SET ultima_mensagem=$1,ultima_atividade=NOW() WHERE id=$2', [resposta, conversaId]);
            }
        }

        res.json({ status: 'ok', conversa_id: conversaId });
    } catch(e) {
        console.error('Webhook error:', e);
        res.status(500).json({ error: e.message });
    }
});

// ===================== CONVERSAS =====================
const TABELAS = ['conversas','contatos','mensagens','modelos','automacoes'];

app.get('/conversas', async (req, res) => {
    try { const r = await pool.query('SELECT c.*, (SELECT COUNT(*) FROM mensagens WHERE conversa_id=c.id AND direcao=\'recebida\' AND lida=false) as nao_lidas FROM conversas c ORDER BY ultima_atividade DESC NULLS LAST'); res.json(r.rows); }
    catch(e) { res.status(500).json({ error: e.message }); }
});

app.get('/conversas/:id/mensagens', async (req, res) => {
    try { const r = await pool.query('SELECT * FROM mensagens WHERE conversa_id=$1 ORDER BY created_at ASC', [req.params.id]); res.json(r.rows); }
    catch(e) { res.status(500).json({ error: e.message }); }
});

app.post('/conversas/:id/mensagens', async (req, res) => {
    const { texto } = req.body;
    if (!texto) return res.status(400).json({ error:'Texto obrigatório' });
    try {
        await pool.query('INSERT INTO mensagens(conversa_id,texto,direcao,origem) VALUES($1,$2,$3,$4)', [req.params.id, texto, 'enviada', 'agente']);
        await pool.query('UPDATE conversas SET ultima_mensagem=$1,ultima_atividade=NOW() WHERE id=$2', [texto, req.params.id]);
        res.json({ success:true });
    } catch(e) { res.status(500).json({ error: e.message }); }
});

// ===================== INTEGRAÇÃO ERP =====================
app.post('/erp/buscar-cliente', async (req, res) => {
    const { telefone } = req.body;
    if (!telefone) return res.status(400).json({ error:'Telefone obrigatório' });
    try {
        // Tenta buscar no ERP Fiscal
        const https = require('https');
        const url = new URL('https://api.projetosdinamicos.com.br/erp/clientes');
        const erpReq = https.get(url, (erpRes) => {
            let data = '';
            erpRes.on('data', chunk => data += chunk);
            erpRes.on('end', () => {
                try {
                    const clientes = JSON.parse(data);
                    const encontrado = (Array.isArray(clientes) ? clientes : []).find(c => {
                        const tel = (c.telefone || '').replace(/\D/g, '');
                        return tel && telefone.replace(/\D/g,'').indexOf(tel.slice(-8)) !== -1;
                    });
                    if (encontrado) {
                        res.json({ encontrado:true, nome:encontrado.nome, documento:encontrado.documento, email:encontrado.email, cidade:encontrado.cidade, uf:encontrado.uf });
                    } else {
                        res.json({ encontrado:false });
                    }
                } catch(e) { res.json({ encontrado:false }); }
            });
        });
        erpReq.on('error', () => res.json({ encontrado:false }));
    } catch(e) { res.json({ encontrado:false }); }
});

// ===================== CRUD GENÉRICO =====================
app.get('/:tabela', async (req, res) => {
    const { tabela } = req.params;
    if (!TABELAS.includes(tabela)) return res.status(404).json({ error:'Tabela não encontrada' });
    try {
        if (tabela === 'mensagens' && req.query.hoje) {
            const r = await pool.query("SELECT * FROM mensagens WHERE created_at::date = CURRENT_DATE ORDER BY id DESC LIMIT 500"); res.json(r.rows);
        } else {
            const r = await pool.query(`SELECT * FROM "${tabela}" ORDER BY id DESC LIMIT 500`); res.json(r.rows);
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.get('/:tabela/:id', async (req, res) => {
    const { tabela, id } = req.params;
    if (!TABELAS.includes(tabela)) return res.status(404).json({ error:'Tabela não encontrada' });
    try { const r = await pool.query(`SELECT * FROM "${tabela}" WHERE id=$1`,[id]); res.json(r.rows[0]||null); }
    catch(e) { res.status(500).json({ error: e.message }); }
});

app.post('/:tabela', async (req, res) => {
    const { tabela } = req.params;
    if (!TABELAS.includes(tabela)) return res.status(404).json({ error:'Tabela não encontrada' });
    const data = req.body;
    try {
        const keys = Object.keys(data).map(k=>`"${k}"`).join(', ');
        const vals = Object.keys(data).map((_,i)=>`$${i+1}`).join(', ');
        const r = await pool.query(`INSERT INTO "${tabela}" (${keys}) VALUES (${vals}) RETURNING *;`, Object.values(data));
        res.json(r.rows[0]);
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.put('/:tabela/:id', async (req, res) => {
    const { tabela, id } = req.params;
    if (!TABELAS.includes(tabela)) return res.status(404).json({ error:'Tabela não encontrada' });
    const data = req.body;
    try {
        const keys = Object.keys(data).map((k,i)=>`"${k}" = $${i+1}`).join(', ');
        const r = await pool.query(`UPDATE "${tabela}" SET ${keys} WHERE id=$${Object.keys(data).length+1} RETURNING *;`, [...Object.values(data), id]);
        res.json(r.rows[0] || { error:'Não encontrado' });
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.delete('/:tabela/:id', async (req, res) => {
    const { tabela, id } = req.params;
    if (!TABELAS.includes(tabela)) return res.status(404).json({ error:'Tabela não encontrada' });
    try { await pool.query(`DELETE FROM "${tabela}" WHERE id=$1`,[id]); res.json({ success:true }); }
    catch(e) { res.status(500).json({ error: e.message }); }
});

// Webhook status
app.get('/webhook/status', async (req, res) => {
    try { const r = await pool.query("SELECT valor FROM settings WHERE chave='ultimo_webhook'"); res.json({ ultimo_webhook: r.rows[0]?.valor||null, online: true }); }
    catch(e) { res.json({ online: false, error: e.message }); }
});

app.listen(PORT, () => {
    console.log(`ERP WhatsApp API running on port ${PORT}`);

    // Inicializa WhatsApp Web.js (não crítico — falha silenciosa se sem Chromium)
    if (!process.env.WHATSAPP_DISABLED) {
        try {
            const wpp = require('./whatsapp');
            wpp.initialize().catch(err => console.warn('[WhatsApp] Inicialização adiada:', err.message));
        } catch(e) {
            console.warn('[WhatsApp] Módulo não disponível:', e.message);
        }
    }
});

// ===================== WHATSAPP QR CODE =====================
app.get('/whatsapp/status', (req, res) => {
    try {
        const wpp = require('./whatsapp');
        res.json(wpp.getStatus());
    } catch(e) {
        res.json({ status: 'unavailable', ready: false, error: 'whatsapp-web.js não carregado' });
    }
});

app.get('/whatsapp/qrcode', (req, res) => {
    try {
        const wpp = require('./whatsapp');
        const qr = wpp.getQrCode();
        if (qr) {
            res.json({ qrcode: qr });
        } else {
            res.json({ qrcode: null, message: 'Nenhum QR Code disponível' });
        }
    } catch(e) {
        res.json({ qrcode: null, error: e.message });
    }
});

app.post('/whatsapp/connect', async (req, res) => {
    try {
        const wpp = require('./whatsapp');
        await wpp.reconnect();
        res.json({ success: true, message: 'Reconectando...' });
    } catch(e) {
        res.status(500).json({ error: e.message });
    }
});

app.post('/whatsapp/logout', async (req, res) => {
    try {
        const wpp = require('./whatsapp');
        await wpp.logout();
        res.json({ success: true, message: 'Desconectado' });
    } catch(e) {
        res.status(500).json({ error: e.message });
    }
});

app.post('/whatsapp/send', async (req, res) => {
    const { to, message } = req.body;
    if (!to || !message) return res.status(400).json({ error: 'to e message obrigatórios' });
    try {
        const wpp = require('./whatsapp');
        await wpp.sendMessage(to, message);
        res.json({ success: true });
    } catch(e) {
        res.status(500).json({ error: e.message });
    }
});
SVREOF
sed -i "s/process\.env\.PORT || 3000/process.env.PORT || $APP_PORT/" "$SRC_DIR/server.js"

# ==============================================================
# whatsapp.js — Serviço WhatsApp Web.js com QR Code
# ==============================================================
info "Criando src/whatsapp.js"
cat > "$SRC_DIR/whatsapp.js" <<'WEOF'
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
WEOF
info "src/whatsapp.js criado"

# ==============================================================
# Configurações — escreve página completa com painel QR Code
# ==============================================================
info "Criando pages/configuracoes.html com painel QR Code..."
mkdir -p "$INSTALL_DIR/pages"
cat > "$INSTALL_DIR/pages/configuracoes.html" <<'HTMLFEOF'
<!DOCTYPE html>
<html lang="pt-br">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Configurações - ERP WhatsApp</title>
  <link rel="stylesheet" href="../static/css/default.css">
  <link rel="stylesheet" href="../static/css/icons/bootstrap-icons.min.css">
  <link rel="icon" type="image/x-icon" href="../static/css/favicon/favicon.ico">
  <script src="../static/js/api.js"></script>
  <script src="../static/js/main.js"></script>
</head>
<body>
  <script>var ROOT='..';</script>
  <script src="../components/header.js"></script>

  <div style="margin-bottom:20px;">
    <h2 style="font-size:1.3rem;color:var(--heading-color);margin:0;">Configurações</h2>
    <p style="font-size:0.85rem;color:var(--text-muted);margin:4px 0 0;">Configurações da plataforma WhatsApp</p>
  </div>

  <div class="card mb-6">
    <div class="card-header">
      <h3 class="card-title"><i class="bi bi-whatsapp"></i> Conexão WhatsApp</h3>
    </div>
    <div class="card-body">
      <form id="wppConfigForm" onsubmit="return salvarConfigWpp(event)">
        <div class="form-row">
          <div class="form-group">
            <label>Número do WhatsApp (ID)</label>
            <input type="text" id="cfgNumero" class="form-control input-phone" placeholder="(14) 99999-0000">
          </div>
          <div class="form-group">
            <label>Token de Acesso</label>
            <input type="password" id="cfgToken" class="form-control" placeholder="Token da API WhatsApp">
          </div>
        </div>
        <div class="form-row">
          <div class="form-group">
            <label>Provider</label>
            <select id="cfgProvider" class="form-control">
              <option value="evolution">Evolution API</option>
              <option value="whatsapp-web">WhatsApp Web.js</option>
              <option value="whatsapp-cloud">WhatsApp Cloud API</option>
              <option value="wwebjs">wwebjs</option>
            </select>
          </div>
          <div class="form-group">
            <label>Webhook URL</label>
            <input type="text" id="cfgWebhook" class="form-control" placeholder="https://api.projetosdinamicos.com.br/whatsapp/webhook">
          </div>
        </div>
        <button type="submit" class="btn btn-primary"><i class="bi bi-check-lg"></i> Salvar</button>
      </form>
    </div>
  </div>

  <!-- PAINEL QR CODE WHATSAPP -->
  <div class="card mb-6">
    <div class="card-header">
      <h3 class="card-title"><i class="bi bi-qr-code-scan"></i> Conexão via QR Code</h3>
    </div>
    <div class="card-body" style="text-align:center;">
      <div id="wppQrStatus" style="margin-bottom:12px;">
        <span class="badge badge-secondary" id="wppStatusBadge">Desconectado</span>
      </div>
      <div id="wppQrContainer" style="display:none; background:#fff; padding:16px; border-radius:8px; display:inline-block; margin:0 auto;">
        <img id="wppQrImage" src="" alt="QR Code" style="width:280px;height:280px;image-rendering:pixelated;">
        <p style="font-size:0.85rem;color:#666;margin-top:8px;">Escaneie o QR Code acima com o WhatsApp do seu celular</p>
      </div>
      <div id="wppConnectedInfo" style="display:none;">
        <i class="bi bi-check-circle-fill" style="font-size:3rem;color:#25D366;"></i>
        <p style="font-size:1rem;color:var(--text-color);margin-top:8px;">WhatsApp conectado!</p>
      </div>
      <div id="wppErrorInfo" style="display:none;">
        <i class="bi bi-exclamation-triangle-fill" style="font-size:3rem;color:#dc3545;"></i>
        <p style="font-size:1rem;color:var(--text-color);margin-top:8px;">Erro na conexão</p>
      </div>
      <div style="margin-top:16px;display:flex;gap:8px;justify-content:center;">
        <button class="btn btn-primary" onclick="conectarWhatsApp()" id="btnWppConnect"><i class="bi bi-plug"></i> Conectar</button>
        <button class="btn btn-danger" onclick="desconectarWhatsApp()" id="btnWppDisconnect" style="display:none;"><i class="bi bi-plug-fill"></i> Desconectar</button>
      </div>
    </div>
  </div>

  <div class="card mb-6">
    <div class="card-header">
      <h3 class="card-title"><i class="bi bi-building"></i> Integração ERP</h3>
    </div>
    <div class="card-body">
      <form id="erpConfigForm" onsubmit="return salvarConfigERP(event)">
        <div class="form-row">
          <div class="form-group">
            <label>URL da API ERP</label>
            <input type="text" id="cfgErpUrl" class="form-control" value="https://api.projetosdinamicos.com.br/erp" placeholder="URL da API do ERP">
          </div>
          <div class="form-group">
            <label>Token ERP</label>
            <input type="password" id="cfgErpToken" class="form-control" placeholder="Token de integração">
          </div>
        </div>
        <div style="display:flex;gap:8px;flex-wrap:wrap;">
          <label class="switch" style="margin-right:8px;">
            <input type="checkbox" id="cfgAutoBusca" checked>
            <span class="slider"></span>
          </label>
          <span style="font-size:0.9rem;">Busca automática de cliente ao receber mensagem</span>
        </div>
        <button type="submit" class="btn btn-primary" style="margin-top:16px;"><i class="bi bi-check-lg"></i> Salvar</button>
      </form>
    </div>
  </div>

  <div class="card mb-6">
    <div class="card-header">
      <h3 class="card-title"><i class="bi bi-chat-square-text"></i> Respostas Padrão</h3>
    </div>
    <div class="card-body">
      <form id="defaultMsgForm" onsubmit="return salvarMsgPadrao(event)">
        <div class="form-group">
          <label>Mensagem de ausência (fora do horário)</label>
          <textarea id="cfgMsgAusencia" class="form-control" rows="2">Olá! No momento estamos fora do horário de atendimento. Deixe sua mensagem que retornaremos em breve.</textarea>
        </div>
        <div class="form-group">
          <label>Mensagem de boas-vindas</label>
          <textarea id="cfgMsgBoasVindas" class="form-control" rows="2">Olá {{nome}}! Bem-vindo(a) ao ERP WhatsApp. Como podemos ajudar?</textarea>
        </div>
        <div class="form-row">
          <div class="form-group">
            <label>Horário de início</label>
            <input type="time" id="cfgHrInicio" class="form-control" value="08:00">
          </div>
          <div class="form-group">
            <label>Horário de fim</label>
            <input type="time" id="cfgHrFim" class="form-control" value="18:00">
          </div>
        </div>
        <button type="submit" class="btn btn-primary"><i class="bi bi-check-lg"></i> Salvar</button>
      </form>
    </div>
  </div>

  <div class="card">
    <div class="card-header">
      <h3 class="card-title"><i class="bi bi-info-circle"></i> Informações do Sistema</h3>
    </div>
    <div class="card-body">
      <div class="form-row-3">
        <div class="form-group">
          <label>Status</label>
          <div><span class="badge badge-success" id="cfgStatus">Online</span></div>
        </div>
        <div class="form-group">
          <label>Versão</label>
          <div><span class="badge badge-info">v1.0.0</span></div>
        </div>
        <div class="form-group">
          <label>Último Webhook</label>
          <div><span class="text-muted" id="cfgLastWebhook">-</span></div>
        </div>
      </div>
    </div>
  </div>

  <script>
  document.getElementById('pageTitle').textContent = 'Configurações';

  API.get('settings').then(function(data) {
    if (data && typeof data === 'object') {
      document.getElementById('cfgNumero').value = data.wpp_numero || '';
      document.getElementById('cfgToken').value = data.wpp_token || '';
      document.getElementById('cfgProvider').value = data.wpp_provider || 'evolution';
      document.getElementById('cfgWebhook').value = data.wpp_webhook || '';
      document.getElementById('cfgErpUrl').value = data.erp_url || '';
      document.getElementById('cfgErpToken').value = data.erp_token || '';
      document.getElementById('cfgAutoBusca').checked = data.auto_busca !== 'false';
      document.getElementById('cfgMsgAusencia').value = data.msg_ausencia || '';
      document.getElementById('cfgMsgBoasVindas').value = data.msg_boasvindas || '';
      document.getElementById('cfgHrInicio').value = data.hr_inicio || '08:00';
      document.getElementById('cfgHrFim').value = data.hr_fim || '18:00';
    }
  }).catch(function() {});

  function salvarConfigWpp(e) {
    e.preventDefault();
    API.post('settings', {
      wpp_numero: document.getElementById('cfgNumero').value,
      wpp_token: document.getElementById('cfgToken').value,
      wpp_provider: document.getElementById('cfgProvider').value,
      wpp_webhook: document.getElementById('cfgWebhook').value
    }).then(function() { showAlert('Configurações WhatsApp salvas!', 'success'); })
      .catch(function(err) { showAlert('Erro: ' + err.message, 'danger'); });
    return false;
  }

  function salvarConfigERP(e) {
    e.preventDefault();
    API.post('settings', {
      erp_url: document.getElementById('cfgErpUrl').value,
      erp_token: document.getElementById('cfgErpToken').value,
      auto_busca: document.getElementById('cfgAutoBusca').checked ? 'true' : 'false'
    }).then(function() { showAlert('Configurações ERP salvas!', 'success'); })
      .catch(function(err) { showAlert('Erro: ' + err.message, 'danger'); });
    return false;
  }

  function salvarMsgPadrao(e) {
    e.preventDefault();
    API.post('settings', {
      msg_ausencia: document.getElementById('cfgMsgAusencia').value,
      msg_boasvindas: document.getElementById('cfgMsgBoasVindas').value,
      hr_inicio: document.getElementById('cfgHrInicio').value,
      hr_fim: document.getElementById('cfgHrFim').value
    }).then(function() { showAlert('Mensagens padrão salvas!', 'success'); })
      .catch(function(err) { showAlert('Erro: ' + err.message, 'danger'); });
    return false;
  }

  /* ===== WhatsApp QR Code ===== */
  var wppCheckInterval = null;

  function atualizarStatusWpp() {
    API.get('whatsapp/status').then(function(s) {
      var badge = document.getElementById('wppStatusBadge');
      var qrContainer = document.getElementById('wppQrContainer');
      var qrImage = document.getElementById('wppQrImage');
      var connectedInfo = document.getElementById('wppConnectedInfo');
      var errorInfo = document.getElementById('wppErrorInfo');
      var btnConnect = document.getElementById('btnWppConnect');
      var btnDisconnect = document.getElementById('btnWppDisconnect');
      if (s.status === 'connected' && s.ready) {
        badge.className = 'badge badge-success';
        badge.textContent = 'Conectado';
        qrContainer.style.display = 'none';
        connectedInfo.style.display = 'block';
        errorInfo.style.display = 'none';
        btnConnect.style.display = 'none';
        btnDisconnect.style.display = 'inline-flex';
        if (wppCheckInterval) { clearInterval(wppCheckInterval); wppCheckInterval = null; }
      } else if (s.status === 'connecting') {
        badge.className = 'badge badge-warning';
        badge.textContent = 'Aguardando leitura...';
        connectedInfo.style.display = 'none';
        errorInfo.style.display = 'none';
        btnConnect.style.display = 'none';
        btnDisconnect.style.display = 'inline-flex';
        if (s.hasQrCode) {
          qrContainer.style.display = 'inline-block';
          API.get('whatsapp/qrcode').then(function(q) {
            if (q.qrcode) qrImage.src = q.qrcode;
          }).catch(function() {});
        }
      } else if (s.status === 'error') {
        badge.className = 'badge badge-danger';
        badge.textContent = 'Erro';
        qrContainer.style.display = 'none';
        connectedInfo.style.display = 'none';
        errorInfo.style.display = 'block';
        btnConnect.style.display = 'inline-flex';
        btnDisconnect.style.display = 'none';
      } else {
        badge.className = 'badge badge-secondary';
        badge.textContent = 'Desconectado';
        qrContainer.style.display = 'none';
        connectedInfo.style.display = 'none';
        errorInfo.style.display = 'none';
        btnConnect.style.display = 'inline-flex';
        btnDisconnect.style.display = 'none';
      }
    }).catch(function() {});
  }

  function conectarWhatsApp() {
    API.post('whatsapp/connect', {}).then(function() {
      showAlert('Conectando ao WhatsApp... Aguarde o QR Code.', 'info');
      atualizarStatusWpp();
      if (!wppCheckInterval) {
        wppCheckInterval = setInterval(atualizarStatusWpp, 3000);
      }
    }).catch(function(err) {
      showAlert('Erro: ' + err.message, 'danger');
    });
  }

  function desconectarWhatsApp() {
    API.post('whatsapp/logout', {}).then(function() {
      showAlert('WhatsApp desconectado.', 'success');
      if (wppCheckInterval) { clearInterval(wppCheckInterval); wppCheckInterval = null; }
      atualizarStatusWpp();
    }).catch(function(err) {
      showAlert('Erro: ' + err.message, 'danger');
    });
  }

  setTimeout(atualizarStatusWpp, 500);
  </script>
  <script src="../components/footer.js"></script>
</body>
</html>
HTMLFEOF
info "pages/configuracoes.html criado"

# ==============================================================
# Nginx
# ==============================================================
info "Configurando Nginx"
if ! grep -q "^# BEGIN $PM2_APP_NAME\$" "$NGINX_CONF" 2>/dev/null; then
  SSL_DIR="/etc/letsencrypt/live"; SSL_CERT=""; SSL_KEY=""
  for d in "$SSL_DIR"/*/; do
    [ -f "${d}fullchain.pem" ] || continue
    if echo "$d" | grep -qi "$(echo "$APP_DOMAIN" | sed 's/^www\.//')"; then
      SSL_CERT="${d}fullchain.pem"; SSL_KEY="${d}privkey.pem"; break
    fi
  done
  [ -z "$SSL_CERT" ] && for d in "$SSL_DIR"/*/; do [ -f "${d}fullchain.pem" ] || continue; SSL_CERT="${d}fullchain.pem"; SSL_KEY="${d}privkey.pem"; break; done
  PROXY_TRAIL="/"; [ "$APP_LOCATION" = "/" ] && PROXY_TRAIL=""

  cat >> "$NGINX_CONF" <<NGINXEOF

# BEGIN $PM2_APP_NAME
server {
    listen 80; listen [::]:80;
    server_name $APP_DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www; }
    location $APP_LOCATION { return 301 https://\$host\$request_uri; }
}
server {
    listen 443 ssl; listen [::]:443 ssl; http2 on;
    server_name $APP_DOMAIN;
NGINXEOF
  [ -n "$SSL_CERT" ] && cat >> "$NGINX_CONF" <<NGINXEOF
    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
NGINXEOF
  cat >> "$NGINX_CONF" <<NGINXEOF
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Content-Type, Authorization" always;
    location /.well-known/acme-challenge/ { root /var/www; }
    location $APP_LOCATION {
        proxy_pass http://127.0.0.1:$APP_PORT$PROXY_TRAIL;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    client_max_body_size 15M;
}
# END $PM2_APP_NAME
NGINXEOF
  info "Nginx configurado"
fi

# ==============================================================
# Migration
# ==============================================================
info "Criando migration..."
MIGRATION_FILE="$INSTALL_DIR/migrations/001_create_tables.sql"
mkdir -p "$INSTALL_DIR/migrations"

cat > "$MIGRATION_FILE" <<SQLEOF
-- ERP WhatsApp — Chatbot integrado ao ERP Fiscal

CREATE TABLE IF NOT EXISTS settings (
    chave VARCHAR(100) PRIMARY KEY,
    valor TEXT
);

CREATE TABLE IF NOT EXISTS contatos (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(255),
    telefone VARCHAR(20) NOT NULL,
    email VARCHAR(255),
    empresa VARCHAR(255),
    observacoes TEXT,
    origem VARCHAR(50) DEFAULT 'manual',
    cliente_erp BOOLEAN DEFAULT FALSE,
    ultima_conversa TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS conversas (
    id SERIAL PRIMARY KEY,
    contato_id INTEGER REFERENCES contatos(id),
    contato_nome VARCHAR(255),
    contato_telefone VARCHAR(20),
    ultima_mensagem TEXT,
    ultima_atividade TIMESTAMP DEFAULT NOW(),
    nao_lidas INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'ativa',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS mensagens (
    id SERIAL PRIMARY KEY,
    conversa_id INTEGER REFERENCES conversas(id) ON DELETE CASCADE,
    contato_id INTEGER REFERENCES contatos(id),
    texto TEXT NOT NULL,
    direcao VARCHAR(20) NOT NULL,
    origem VARCHAR(50) DEFAULT 'contato',
    lida BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS modelos (
    id SERIAL PRIMARY KEY,
    titulo VARCHAR(255) NOT NULL,
    categoria VARCHAR(50) DEFAULT 'Outro',
    conteudo TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'Ativo',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS automacoes (
    id SERIAL PRIMARY KEY,
    gatilho VARCHAR(255) NOT NULL,
    tipo VARCHAR(50) DEFAULT 'consulta',
    modelo_id INTEGER REFERENCES modelos(id),
    resposta TEXT,
    prioridade INTEGER DEFAULT 2,
    ativo VARCHAR(10) DEFAULT 'Sim',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS usuarios (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    senha VARCHAR(255) NOT NULL,
    tipo VARCHAR(50) DEFAULT 'admin',
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO settings (chave, valor) VALUES
    ('versao_plataforma', '1.0.0'),
    ('bot_ativo', 'true'),
    ('msg_boasvindas', 'Olá {{nome}}! Bem-vindo(a) ao ERP WhatsApp. Como podemos ajudar?'),
    ('msg_ausencia', 'Olá! No momento estamos fora do horário de atendimento. Deixe sua mensagem que retornaremos em breve.'),
    ('hr_inicio', '08:00'),
    ('hr_fim', '18:00'),
    ('wpp_provider', 'whatsapp-web'),
    ('wpp_webhook', 'https://api.projetosdinamicos.com.br/whatsapp/webhook'),
    ('erp_url', 'https://api.projetosdinamicos.com.br/erp'),
    ('wpp_session_status', 'disconnected'),
    ('chromium_path', '$CHROMIUM_PATH')
ON CONFLICT (chave) DO NOTHING;

INSERT INTO usuarios (nome, email, senha, tipo)
VALUES ('${ADMIN_NOME}', '${ADMIN_EMAIL}', '${ADMIN_PASS}', 'admin')
ON CONFLICT (email) DO NOTHING;

-- Modelos padrão
INSERT INTO modelos (titulo, categoria, conteudo) VALUES
    ('Saudação Inicial', 'Boas-vindas', 'Olá {{nome}}! Tudo bem? 😊 Sou o assistente virtual do ERP. Como posso ajudar você hoje?'),
    ('Consulta de Produto', 'Vendas', 'Olá {{nome}}! Para consultar produtos, por favor informe o código ou nome do produto que deseja.'),
    ('Suporte Técnico', 'Suporte', 'Olá {{nome}}! Abrimos um chamado de suporte para você. Em breve nossa equipe retornará.')
ON CONFLICT DO NOTHING;

-- Regras de automação padrão
INSERT INTO automacoes (gatilho, tipo, resposta, prioridade) VALUES
    ('olá', 'saudacao', 'Olá {{nome}}! Como posso ajudar? 😊', 1),
    ('preço', 'consulta', 'Olá {{nome}}! Deseja consultar preços? Informe o código do produto.', 2),
    ('suporte', 'suporte', 'Olá {{nome}}! Vou abrir um chamado de suporte para você.', 2)
ON CONFLICT DO NOTHING;
SQLEOF

if command -v sudo >/dev/null 2>&1 && sudo -u postgres psql -c "SELECT 1" >/dev/null 2>&1; then
  if [ "$DB_USER" != "postgres" ]; then
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" 2>/dev/null || true
  fi
  sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || warn "Banco já existe"
  PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$MIGRATION_FILE" 2>/dev/null && \
    info "Migration executada!" || warn "Erro na migration"
else
  warn "Migration não executada automaticamente"
fi

# ==============================================================
# Dependências, PM2, Nginx reload
# ==============================================================
info "Instalando dependências Node.js"
if [ -n "$CHROMIUM_PATH" ]; then
  PUPPETEER_SKIP_DOWNLOAD=true PUPPETEER_EXECUTABLE_PATH="$CHROMIUM_PATH" npm install --prefix "$INSTALL_DIR" --production
else
  npm install --prefix "$INSTALL_DIR" --production
fi

info "Registrando no PM2"
$PM2_AS_USER pm2 delete "$PM2_APP_NAME" 2>/dev/null || true
if [ -n "$CHROMIUM_PATH" ]; then
  $PM2_AS_USER pm2 start "$INSTALL_DIR/src/server.js" --name "$PM2_APP_NAME" --env CHROMIUM_PATH="$CHROMIUM_PATH"
else
  $PM2_AS_USER pm2 start "$INSTALL_DIR/src/server.js" --name "$PM2_APP_NAME"
fi
$PM2_AS_USER pm2 save --force

info "Recarregando Nginx"
nginx -t && systemctl reload nginx 2>/dev/null && info "Nginx OK" || warn "Falha nginx"

echo ""
info "==========================================="
info " Instalação ERP WhatsApp concluída!"
info "==========================================="
echo ""
echo "  Domínio:   $APP_DOMAIN"
echo "  Location:  $APP_LOCATION"
echo "  Porta:     $APP_PORT"
echo "  PM2:       $PM2_APP_NAME"
echo ""
echo "  Endpoints:"
    echo "    GET   ${APP_LOCATION}"
    echo "    POST  ${APP_LOCATION}auth/login"
    echo "    POST  ${APP_LOCATION}webhook            ← Webhook WhatsApp"
    echo "    GET   ${APP_LOCATION}conversas"
    echo "    GET   ${APP_LOCATION}contatos"
    echo "    GET   ${APP_LOCATION}modelos"
    echo "    GET   ${APP_LOCATION}automacoes"
    echo "    POST  ${APP_LOCATION}erp/buscar-cliente ← Integração ERP"
    echo "    GET   ${APP_LOCATION}whatsapp/status    ← Status conexão WhatsApp"
    echo "    GET   ${APP_LOCATION}whatsapp/qrcode    ← QR Code (base64) para scan"
    echo "    POST  ${APP_LOCATION}whatsapp/connect   ← (Re)conectar WhatsApp"
    echo "    POST  ${APP_LOCATION}whatsapp/logout    ← Desconectar WhatsApp"
    echo "    POST  ${APP_LOCATION}whatsapp/send      ← Enviar mensagem via WhatsApp real"
    echo ""
    echo "  QR Code:"
    echo "    - O QR Code aparece automaticamente no TERMINAL ao iniciar"
    echo "    - Também disponível via API e na página de Configurações"
    echo ""
    echo "  Admin: $ADMIN_EMAIL / $ADMIN_PASS"
echo ""
info "Testando API..."
sleep 2
BASE="http://127.0.0.1:$APP_PORT/"
curl -s "${BASE}health" 2>/dev/null | grep -q '"healthy"' && info "Health: ✓" || warn "Health: ✗"
# Test webhook
WEBHOOK_TEST=$(curl -s -X POST "${BASE}webhook" -H "Content-Type: application/json" \
  -d '{"from":"5514999999999","name":"Cliente Teste","message":"Olá, gostaria de informações"}' 2>/dev/null)
echo "$WEBHOOK_TEST" | grep -q '"ok"' && info "Webhook: ✓" || warn "Webhook: ✗ $WEBHOOK_TEST"
# Test WhatsApp status
WPP_STATUS=$(curl -s "${BASE}whatsapp/status" 2>/dev/null)
echo "$WPP_STATUS" | grep -q '"status"' && info "WhatsApp Status: ✓" || warn "WhatsApp Status: ✗"
info "Testes concluídos!"
