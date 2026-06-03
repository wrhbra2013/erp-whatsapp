document.write('\
    </main>\
    <div class="status-bar">\
      <span><span id="wppStatusDot" style="width:8px;height:8px;border-radius:50%;display:inline-block;background:var(--brand-success);"></span> WhatsApp <span id="wppStatusText">Conectado</span></span>\
      <span id="clockDisplay"></span>\
      <span style="margin-left:auto;">ERP WhatsApp v1.0.0</span>\
    </div>\
  </div>\
</div>\
');

(function() {
  var user = API.getUser();
  var ud = document.getElementById('userDisplay');
  if (ud && user) ud.textContent = user.nome || user.email;

  var clock = document.getElementById('clockDisplay');
  if (clock) {
    function update() { clock.textContent = new Date().toLocaleString('pt-BR'); }
    update(); setInterval(update, 1000);
  }

  var statusDot = document.getElementById('wppStatusDot');
  var statusText = document.getElementById('wppStatusText');
  var wppBadge = document.getElementById('wppStatus');

  function checkStatus() {
    API.get('status').then(function(s) {
      var connected = s && (s.status === 'connected' || s.ready);
      if (statusDot) statusDot.style.background = connected ? 'var(--brand-success)' : 'var(--brand-warning)';
      if (statusText) statusText.textContent = connected ? 'Conectado' : (s && s.status === 'connecting' ? 'Conectando...' : 'Desconectado');
      if (wppBadge) {
        wppBadge.className = 'badge ' + (connected ? 'badge-success' : (s && s.status === 'connecting' ? 'badge-warning' : 'badge-danger'));
        wppBadge.textContent = connected ? 'WhatsApp Conectado' : (s && s.status === 'connecting' ? 'Conectando...' : 'Desconectado');
      }
    }).catch(function() {
      if (statusDot) statusDot.style.background = 'var(--brand-danger)';
      if (statusText) statusText.textContent = 'API Offline';
      if (wppBadge) { wppBadge.className = 'badge badge-danger'; wppBadge.textContent = 'API Offline'; }
    });
  }

  checkStatus();
  setInterval(checkStatus, 15000);
})();
