document.write('\
<div class="app-layout">\
  <div id="sidebarOverlay" class="sidebar-overlay"></div>\
  <aside id="sidebar" class="sidebar">\
    <div class="sidebar-logo">\
      <h2><span>ERP</span> WhatsApp</h2>\
      <div style="font-size:0.7rem;color:rgba(255,255,255,0.4);margin-top:2px;">Chatbot Inteligente</div>\
    </div>\
    <nav class="sidebar-nav">\
      <div class="nav-section">Principal</div>\
      <a href="index.html"><i class="bi bi-chat-dots"></i> Dashboard</a>\
      <a href="pages/conversas.html"><i class="bi bi-chat-square-text"></i> Conversas</a>\
      <div class="nav-section">Gestão</div>\
      <a href="pages/contatos.html"><i class="bi bi-people"></i> Contatos</a>\
      <a href="pages/modelos.html"><i class="bi bi-file-earmark-text"></i> Modelos de Mensagem</a>\
      <a href="pages/automacao.html"><i class="bi bi-gear-wide-connected"></i> Automação</a>\
      <div class="nav-section">Relatórios</div>\
      <a href="pages/relatorios.html"><i class="bi bi-bar-chart"></i> Relatórios</a>\
      <div class="nav-section">Sistema</div>\
      <a href="pages/configuracoes.html"><i class="bi bi-gear"></i> Configurações</a>\
      <a href="#" onclick="API.logout();return false;"><i class="bi bi-box-arrow-right"></i> Sair</a>\
    </nav>\
  </aside>\
  <div class="main-area">\
    <header class="topbar">\
      <div class="topbar-left">\
        <button id="menuToggle" class="menu-toggle"><i class="bi bi-list"></i></button>\
        <span id="pageTitle" style="font-weight:600;font-size:1.05rem;">Dashboard</span>\
      </div>\
      <div class="topbar-right">\
        <span style="font-size:0.85rem;color:var(--text-muted);" id="userDisplay"></span>\
        <span id="wppStatus" class="badge badge-success" style="font-size:0.7rem;">WhatsApp Conectado</span>\
      </div>\
    </header>\
    <main class="page-content">');
