document.addEventListener('DOMContentLoaded', function() {
  var menuToggle = document.getElementById('menuToggle');
  var sidebar = document.getElementById('sidebar');
  var sidebarOverlay = document.getElementById('sidebarOverlay');

  if (menuToggle && sidebar) {
    menuToggle.addEventListener('click', function() {
      sidebar.classList.toggle('open');
      if (sidebarOverlay) sidebarOverlay.classList.toggle('active');
    });
  }

  if (sidebarOverlay) {
    sidebarOverlay.addEventListener('click', function() {
      sidebar.classList.remove('open');
      sidebarOverlay.classList.remove('active');
    });
  }

  var currentPath = window.location.pathname;
  document.querySelectorAll('.sidebar-nav a').forEach(function(link) {
    var href = link.getAttribute('href');
    if (href && currentPath.indexOf(href) !== -1) link.classList.add('active');
  });

  // Format phone inputs
  document.querySelectorAll('.input-phone').forEach(function(input) {
    input.addEventListener('input', function() {
      var v = this.value.replace(/\D/g, '').slice(0, 13);
      if (v.length <= 10) {
        this.value = v.replace(/(\d{2})(\d{4})(\d{4})/, '($1) $2-$3');
      } else if (v.length === 11) {
        this.value = v.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
      } else {
        this.value = v.replace(/(\d{2})(\d{4})(\d{4})/, '($1) $2-$3');
      }
    });
  });
});

function formatPhone(v) {
  if (!v) return '-';
  var s = v.replace(/\D/g, '');
  if (s.length === 11) return s.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
  if (s.length <= 10) return s.replace(/(\d{2})(\d{4})(\d{4})/, '($1) $2-$3');
  return s;
}

function formatDate(d) {
  if (!d) return '-';
  return new Date(d).toLocaleDateString('pt-BR');
}

function formatDateTime(d) {
  if (!d) return '-';
  return new Date(d).toLocaleString('pt-BR');
}

function showAlert(msg, type) {
  type = type || 'success';
  var container = document.getElementById('alertContainer');
  if (!container) {
    container = document.createElement('div');
    container.id = 'alertContainer';
    container.style.cssText = 'position:fixed;top:20px;right:20px;z-index:9999;';
    document.body.appendChild(container);
  }
  var el = document.createElement('div');
  el.className = 'alert alert-' + type;
  el.textContent = msg;
  el.style.cssText = 'margin-bottom:8px;box-shadow:0 4px 12px rgba(0,0,0,0.15);';
  container.appendChild(el);
  setTimeout(function() { el.remove(); }, 4000);
}
