/**
 * app.js
 * Controls light/dark mode switcher, terminal command tab switching,
 * click-to-copy, and physical keycap press feedback animations.
 */

(function () {
  // ── 1. Theme Switcher (Light / Dark) with LocalStorage persistence ─────────
  const themeToggle = document.getElementById('theme-toggle');
  const htmlRoot = document.documentElement;

  // Light is the site default. An explicit choice remains persisted.
  const savedTheme = localStorage.getItem('trackpad-theme');
  if (savedTheme) {
    htmlRoot.setAttribute('data-theme', savedTheme);
  }

  if (themeToggle) {
    themeToggle.addEventListener('click', () => {
      const current = htmlRoot.getAttribute('data-theme') || 'dark';
      const next = current === 'dark' ? 'light' : 'dark';
      htmlRoot.setAttribute('data-theme', next);
      localStorage.setItem('trackpad-theme', next);
    });
  }

  // ── 2. Terminal Command Tabs & Click-to-Copy ───────────────────────────────
  const tabs = document.querySelectorAll('.cmd-tab');
  const cmdText = document.getElementById('cmd-text');
  const copyBtn = document.getElementById('copy-btn');

  const commands = {
    brew: 'brew install --cask rajanraj2/tap/trackpad-toggle',
    npx: 'npx trackpad-toggle'
  };

  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      tabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      const key = tab.getAttribute('data-tab');
      if (cmdText && commands[key]) {
        cmdText.textContent = commands[key];
      }
    });
  });

  if (copyBtn && cmdText) {
    copyBtn.addEventListener('click', async () => {
      const textToCopy = cmdText.textContent.trim();
      try {
        await navigator.clipboard.writeText(textToCopy);
        copyBtn.classList.add('copied');
        setTimeout(() => {
          copyBtn.classList.remove('copied');
        }, 2000);
      } catch (err) {
        // Fallback for older browsers
        const textarea = document.createElement('textarea');
        textarea.value = textToCopy;
        document.body.appendChild(textarea);
        textarea.select();
        document.execCommand('copy');
        document.body.removeChild(textarea);
        copyBtn.classList.add('copied');
        setTimeout(() => {
          copyBtn.classList.remove('copied');
        }, 2000);
      }
    });
  }

  // ── 3. Sequential Keypress Animation & Interactive Clusters ────────────────
  const clusterTouchpad = document.getElementById('cluster-touchpad');
  const clusterFull = document.getElementById('cluster-full');
  const statusTouchpad = document.getElementById('status-touchpad');
  const statusFull = document.getElementById('status-full');

  let touchpadDisabled = false;
  let fullLocked = false;

  /**
   * Plays a smooth sequential typing animation where keys press down one by one,
   * hold momentarily, then release together to trigger the state toggle.
   */
  async function playSequentialPress(cluster, onComplete) {
    if (!cluster || cluster.dataset.animating === 'true') return;
    cluster.dataset.animating = 'true';

    const caps = Array.from(cluster.querySelectorAll('.keycap'));
    const delays = [0, 220, 440, 680]; // Control -> Option -> Command -> T/K

    caps.forEach(cap => cap.classList.remove('active'));

    // Press down one by one
    for (let i = 0; i < caps.length; i++) {
      await new Promise(r => setTimeout(r, i === 0 ? delays[0] : delays[i] - delays[i - 1]));
      caps[i].classList.add('active');
    }

    // Hold the complete chord
    await new Promise(r => setTimeout(r, 260));

    // Release all simultaneously
    caps.forEach(cap => cap.classList.remove('active'));

    if (onComplete) onComplete();
    cluster.dataset.animating = 'false';
  }

  function toggleTouchpadState() {
    touchpadDisabled = !touchpadDisabled;
    if (statusTouchpad) {
      const text = statusTouchpad.querySelector('.status-text');
      if (touchpadDisabled) {
        statusTouchpad.className = 'showcase-status active-state';
        if (text) text.textContent = 'Trackpad Frozen • ⌃⌥⌘T to unlock';
      } else {
        statusTouchpad.className = 'showcase-status';
        if (text) text.textContent = 'Touchpad Active • Press sequence to toggle';
      }
    }
  }

  function toggleFullLockState() {
    fullLocked = !fullLocked;
    if (statusFull) {
      const text = statusFull.querySelector('.status-text');
      if (fullLocked) {
        statusFull.className = 'showcase-status locked-state';
        if (text) text.textContent = 'Keyboard & Trackpad Locked • ⌃⌥⌘K to unlock';
      } else {
        statusFull.className = 'showcase-status';
        if (text) text.textContent = 'Inputs Unlocked • Press sequence to lock';
      }
    }
  }

  // Clicking either cluster replays its sequential keypress animation and state toggle
  if (clusterTouchpad) {
    clusterTouchpad.addEventListener('click', () => {
      playSequentialPress(clusterTouchpad, toggleTouchpadState);
    });
  }

  if (clusterFull) {
    clusterFull.addEventListener('click', () => {
      playSequentialPress(clusterFull, toggleFullLockState);
    });
  }

  // Continuous loop: alternates between Touchpad (⌃⌥⌘T) and Full Lock (⌃⌥⌘K)
  let nextDemo = 'touchpad';

  async function runContinuousAnimationLoop() {
    // Only animate when tab is visible
    if (document.visibilityState === 'visible') {
      if (nextDemo === 'touchpad' && clusterTouchpad) {
        await playSequentialPress(clusterTouchpad, toggleTouchpadState);
        nextDemo = 'full';
      } else if (clusterFull) {
        await playSequentialPress(clusterFull, toggleFullLockState);
        nextDemo = 'touchpad';
      }
    }
    // Brief pause between loops before typing the next shortcut
    setTimeout(runContinuousAnimationLoop, 1400);
  }

  // Start loop on initial load
  setTimeout(runContinuousAnimationLoop, 600);

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      setTimeout(runContinuousAnimationLoop, 400);
    }
  });
  const allKeycaps = document.querySelectorAll('.keycap');
  window.addEventListener('keydown', (e) => {
    allKeycaps.forEach(cap => {
      const key = cap.getAttribute('data-key');
      if (key === 'Control' && e.ctrlKey) cap.classList.add('active');
      if (key === 'Alt' && e.altKey) cap.classList.add('active');
      if (key === 'Meta' && e.metaKey) cap.classList.add('active');
      if ((key === 't' || key === 'T') && (e.key === 't' || e.key === 'T')) {
        cap.classList.add('active');
        if (e.ctrlKey && e.altKey && e.metaKey) toggleTouchpadState();
      }
      if ((key === 'k' || key === 'K') && (e.key === 'k' || e.key === 'K')) {
        cap.classList.add('active');
        if (e.ctrlKey && e.altKey && e.metaKey) toggleFullLockState();
      }
    });
  });

  window.addEventListener('keyup', (e) => {
    allKeycaps.forEach(cap => {
      const key = cap.getAttribute('data-key');
      if (key === 'Control' && !e.ctrlKey) cap.classList.remove('active');
      if (key === 'Alt' && !e.altKey) cap.classList.remove('active');
      if (key === 'Meta' && !e.metaKey) cap.classList.remove('active');
      if ((key === 't' || key === 'T') && (e.key === 't' || e.key === 'T')) cap.classList.remove('active');
      if ((key === 'k' || key === 'K') && (e.key === 'k' || e.key === 'K')) cap.classList.remove('active');
    });
  });

  // ── 4. Card Tilt & Ambient Hover Micro-interactions ────────────────────────
  const interactiveCards = document.querySelectorAll('.pillar-card, .showcase-box');
  interactiveCards.forEach(card => {
    card.addEventListener('mousemove', (e) => {
      const rect = card.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      const centerX = rect.width / 2;
      const centerY = rect.height / 2;
      const rotateX = ((y - centerY) / centerY) * -3;
      const rotateY = ((x - centerX) / centerX) * 3;
      card.style.transform = `perspective(800px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) translateY(-2px)`;
    });

    card.addEventListener('mouseleave', () => {
      card.style.transform = '';
    });
  });

  // ── 5. Smooth Anchor Scrolling ─────────────────────────────────────────────
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
      const targetId = this.getAttribute('href');
      if (targetId === '#') return;
      const target = document.querySelector(targetId);
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth' });
      }
    });
  });

  // ── 6. Live Unique Visitor Counter & Client Observability ──────────────────
  const visitorCountEl = document.getElementById('visitor-count');

  async function initVisitorCounter() {
    if (!visitorCountEl) return;

    // Differentiate human vs bot on client side:
    // Automation tools typically set navigator.webdriver == true
    const isAutomated = navigator.webdriver ||
                        !window.crypto ||
                        /bot|googlebot|crawler|spider|robot|crawling/i.test(navigator.userAgent);

    // Session-based deduplication: count uniquely once per human browser session
    const hasVisitedThisSession = sessionStorage.getItem('tt_session_recorded');

    try {
      let countNumber = null;

      if (!hasVisitedThisSession && !isAutomated) {
        // New unique human visitor in this session -> increment counter
        const res = await fetch('https://counterapi.com/api/trackpad-toggle.rajanraj.me/view/visitors');
        if (res.ok) {
          const data = await res.json();
          if (data && typeof data.value === 'number') {
            countNumber = data.value;
            sessionStorage.setItem('tt_session_recorded', '1');
            localStorage.setItem('tt_cached_visitors', String(countNumber));
          }
        }
      }

      // If already recorded or increment failed, read cached or fallback to hits.sh
      if (!countNumber) {
        const cached = localStorage.getItem('tt_cached_visitors');
        if (cached) {
          countNumber = parseInt(cached, 10);
        } else {
          // Fetch current count via hits.sh svg badge parser
          const hitsRes = await fetch('https://hits.sh/trackpad-toggle.rajanraj.me.svg', { cache: 'no-cache' });
          if (hitsRes.ok) {
            const svgText = await hitsRes.text();
            const match = svgText.match(/aria-label="hits:\s*([0-9,]+)"/i);
            if (match && match[1]) {
              countNumber = parseInt(match[1].replace(/,/g, ''), 10);
            }
          }
        }
      }

      if (countNumber && !isNaN(countNumber)) {
        visitorCountEl.textContent = Number(countNumber).toLocaleString();
      } else {
        visitorCountEl.textContent = 'Active';
      }
    } catch (err) {
      // Fallback display gracefully without breaking UI
      const cached = localStorage.getItem('tt_cached_visitors');
      visitorCountEl.textContent = cached ? Number(cached).toLocaleString() : 'Active';
    }
  }

  // ── 7. Client Observability: Performance & Conversion Event Tracking ──────
  function recordEvent(category, action, label) {
    // 1. Dispatch to global dataLayer if analytics beacon (e.g. Cloudflare / GA) is present
    if (window.dataLayer && Array.isArray(window.dataLayer)) {
      window.dataLayer.push({ event: action, category, label });
    }

    // 2. Persist conversion event counters in CounterAPI (viewable via JSON API & dashboard)
    if (action === 'Download_DMG_Click') {
      fetch('https://counterapi.com/api/trackpad-toggle.rajanraj.me/click/download-dmg').catch(() => {});
    } else if (action === 'Copy_Command_Click') {
      const key = label === 'brew' ? 'copy-brew' : 'copy-npx';
      fetch(`https://counterapi.com/api/trackpad-toggle.rajanraj.me/click/${key}`).catch(() => {});
    }

    console.debug(`[Telemetry] ${category} -> ${action}: ${label || ''}`);
  }

  // Track primary download button conversion
  const downloadBtn = document.querySelector('.primary-download-btn');
  if (downloadBtn) {
    downloadBtn.addEventListener('click', () => {
      recordEvent('Conversion', 'Download_DMG_Click', 'TrackpadToggle.dmg');
    });
  }

  // Track command copy actions
  if (copyBtn) {
    copyBtn.addEventListener('click', () => {
      const activeTab = document.querySelector('.cmd-tab.active');
      const tabName = activeTab ? activeTab.dataset.tab : 'brew';
      recordEvent('Engagement', 'Copy_Command_Click', tabName);
    });
  }
  // Track page load performance (Navigation Timing API)
  window.addEventListener('load', () => {
    initVisitorCounter();

    if (window.performance && performance.getEntriesByType) {
      const navEntries = performance.getEntriesByType('navigation');
      if (navEntries.length > 0) {
        const nav = navEntries[0];
        const ttfb = Math.round(nav.responseStart - nav.requestStart);
        const domReady = Math.round(nav.domContentLoadedEventEnd - nav.startTime);
        const loadTime = Math.round(nav.loadEventEnd - nav.startTime);
        recordEvent('Performance', 'PageLoadMetrics', `TTFB: ${ttfb}ms, DOM: ${domReady}ms, Total: ${loadTime}ms`);
      }
    }
  });
})();
