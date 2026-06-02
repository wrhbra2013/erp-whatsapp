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
})();
