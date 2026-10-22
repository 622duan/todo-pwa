// todo · 自定义下拉刷新 + 强制刷新
// 因为 iOS PWA body 有 overflow: hidden，原生下拉刷新失效
// 监听 touch 事件，在 .scroll-area 顶部下拉触发 location.reload()

(function () {
  // Inject refresh indicator HTML
  const indicator = document.createElement('div');
  indicator.id = 'ptr-indicator';
  indicator.innerHTML = `
    <div class="ptr-spinner"><i class="fas fa-arrows-rotate"></i></div>
    <span class="ptr-text">下拉刷新</span>
  `;
  document.body.appendChild(indicator);

  // Inject styles
  const style = document.createElement('style');
  style.textContent = `
    #ptr-indicator {
      position: fixed;
      top: 0;
      left: 50%;
      transform: translateX(-50%) translateY(-60px);
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 10px 18px;
      background: rgba(15, 23, 42, 0.92);
      color: #fff;
      border-radius: 999px;
      font-size: 13px;
      font-weight: 500;
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.2);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      z-index: 9999;
      transition: transform 0.25s cubic-bezier(0.25, 0.46, 0.45, 0.94);
      pointer-events: none;
    }
    #ptr-indicator.ptr-ready { transform: translateX(-50%) translateY(20px); }
    #ptr-indicator.ptr-refresh {
      transform: translateX(-50%) translateY(20px);
      background: rgba(132, 169, 140, 0.95);
    }
    .ptr-spinner {
      display: inline-block;
      transition: transform 0.3s;
    }
    #ptr-indicator.ptr-ready .ptr-spinner { transform: rotate(180deg); }
    #ptr-indicator.ptr-refresh .ptr-spinner {
      animation: ptr-rotate 0.8s linear infinite;
    }
    @keyframes ptr-rotate {
      from { transform: rotate(0deg); }
      to { transform: rotate(360deg); }
    }
  `;
  document.head.appendChild(style);

  // Find the scrollable area
  function getScrollEl() {
    return document.querySelector('.scroll-area') || document.body;
  }

  let startY = 0;
  let currentY = 0;
  let isDragging = false;
  let isReady = false;
  const THRESHOLD = 70; // px to pull to trigger refresh

  const scrollEl = getScrollEl();

  scrollEl.addEventListener('touchstart', (e) => {
    if (scrollEl.scrollTop > 5) return; // Only at top
    startY = e.touches[0].clientY;
    isDragging = true;
    isReady = false;
  }, { passive: true });

  scrollEl.addEventListener('touchmove', (e) => {
    if (!isDragging) return;
    if (scrollEl.scrollTop > 5) {
      isDragging = false;
      return;
    }
    currentY = e.touches[0].clientY;
    const delta = currentY - startY;
    if (delta < 0) return; // Only pull down

    if (delta > THRESHOLD && !isReady) {
      isReady = true;
      indicator.classList.add('ptr-ready');
      document.querySelector('.ptr-text').textContent = '释放刷新';
    } else if (delta <= THRESHOLD && isReady) {
      isReady = false;
      indicator.classList.remove('ptr-ready');
      document.querySelector('.ptr-text').textContent = '下拉刷新';
    }
  }, { passive: true });

  scrollEl.addEventListener('touchend', (e) => {
    if (!isDragging) return;
    isDragging = false;

    if (isReady) {
      // Trigger refresh
      indicator.classList.remove('ptr-ready');
      indicator.classList.add('ptr-refresh');
      document.querySelector('.ptr-text').textContent = '刷新中…';

      // Force reload bypassing cache
      setTimeout(() => {
        // Clear cache for this page and force reload
        if ('serviceWorker' in navigator) {
          navigator.serviceWorker.getRegistrations().then(regs => {
            regs.forEach(r => r.update());
          });
        }
        location.reload();
      }, 400);
    } else {
      indicator.classList.remove('ptr-ready');
    }
  }, { passive: true });

  // Expose manual refresh function
  window.manualRefresh = function () {
    indicator.classList.add('ptr-refresh');
    document.querySelector('.ptr-text').textContent = '刷新中…';
    setTimeout(() => {
      if ('serviceWorker' in navigator) {
        navigator.serviceWorker.getRegistrations().then(regs => {
          regs.forEach(r => r.update());
        });
      }
      location.reload();
    }, 300);
  };
})();
