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

  // ── 3. Physical Keycap Press Animations ─────────────────────────────────────
  const keyCluster = document.getElementById('key-cluster');
  const keycaps = document.querySelectorAll('.keycap');

  if (keyCluster) {
    // Physical hardware keyboard listener: lighting up the on-screen keys
    window.addEventListener('keydown', (e) => {
      keycaps.forEach(cap => {
        const key = cap.getAttribute('data-key');
        if (key === 'Control' && e.ctrlKey) cap.classList.add('active');
        if (key === 'Alt' && e.altKey) cap.classList.add('active');
        if (key === 'Meta' && e.metaKey) cap.classList.add('active');
        if ((key === 't' || key === 'T') && (e.key === 't' || e.key === 'T')) cap.classList.add('active');
      });
    });

    window.addEventListener('keyup', (e) => {
      keycaps.forEach(cap => {
        const key = cap.getAttribute('data-key');
        if (key === 'Control' && !e.ctrlKey) cap.classList.remove('active');
        if (key === 'Alt' && !e.altKey) cap.classList.remove('active');
        if (key === 'Meta' && !e.metaKey) cap.classList.remove('active');
        if ((key === 't' || key === 'T') && (e.key === 't' || e.key === 'T')) cap.classList.remove('active');
      });
    });

    // Clicking keycaps manually in browser triggers tactile feedback
    keycaps.forEach(cap => {
      cap.addEventListener('click', () => {
        cap.classList.add('active');
        setTimeout(() => cap.classList.remove('active'), 180);
      });
    });
  }

  // ── 4. Smooth Anchor Scrolling ─────────────────────────────────────────────
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
})();
