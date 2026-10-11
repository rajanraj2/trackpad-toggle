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

  // Periodic auto-demonstration: alternates playing the keypress animations
  let autoPlayTimer = null;
  let nextDemo = 'touchpad';

  function startAutoDemo() {
    autoPlayTimer = setTimeout(() => {
      // Only run auto demo if the user is not actively typing or interacting
      if (document.visibilityState === 'visible') {
        if (nextDemo === 'touchpad' && clusterTouchpad) {
          playSequentialPress(clusterTouchpad, toggleTouchpadState);
          nextDemo = 'full';
        } else if (clusterFull) {
          playSequentialPress(clusterFull, toggleFullLockState);
          nextDemo = 'touchpad';
        }
      }
      startAutoDemo();
    }, 6000);
  }

  // User interaction temporarily delays auto demo
  function resetAutoDemo() {
    clearTimeout(autoPlayTimer);
    startAutoDemo();
  }

  window.addEventListener('click', resetAutoDemo);
  window.addEventListener('keydown', resetAutoDemo);
  startAutoDemo();

  // Live hardware keyboard listener: lights up the respective keycaps
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
})();
