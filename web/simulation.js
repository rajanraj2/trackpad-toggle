/**
 * simulation.js
 * High-performance 60fps dual-canvas simulation of the MacBook cleaning wipe problem & solution.
 * Left Canvas: macOS Desktop with flying cursor vs locked cursor.
 * Right Canvas: MacBook hardware top case, keyboard, glass trackpad, and wiping microfiber cloth.
 */

(function () {
  const screenCanvas = document.getElementById('screen-canvas');
  const hwCanvas = document.getElementById('hardware-canvas');
  if (!screenCanvas || !hwCanvas) return;

  const sCtx = screenCanvas.getContext('2d');
  const hCtx = hwCanvas.getContext('2d');

  // UI state hooks
  const toggleBtn = document.getElementById('sim-toggle-btn');
  const statusText = document.getElementById('sim-status-text');
  const screenBadge = document.getElementById('screen-badge');
  const hwBadge = document.getElementById('hardware-badge');
  const driftVal = document.getElementById('drift-val');
  const clicksVal = document.getElementById('clicks-val');
  const hwSummary = document.getElementById('hardware-summary');

  // Simulation State
  let isLocked = false;
  let userIsDragging = false;
  let customDragPos = { x: 0, y: 0 };

  // Wiping motion physics
  let time = 0;
  let clothPos = { x: 300, y: 240 };
  let targetClothPos = { x: 300, y: 240 };

  // Screen cursor physics
  let cursor = {
    x: 300,
    y: 190,
    targetX: 300,
    targetY: 190,
    lockedX: 300,
    lockedY: 190,
    trail: []
  };

  // Metrics
  let totalDrift = 128;
  let misclicks = 14;

  // Window Mock Objects on the simulated desktop
  const mockWindows = [
    { x: 60, y: 50, w: 260, h: 160, title: 'Document.txt', color: '#1E2530', selected: false },
    { x: 280, y: 90, w: 250, h: 170, title: 'Code Editor', color: '#161B22', selected: false }
  ];

  // ── Toggle Function ────────────────────────────────────────────────────────
  function setLockedState(locked) {
    isLocked = locked;
    if (isLocked) {
      // Lock down cursor position
      cursor.lockedX = cursor.x;
      cursor.lockedY = cursor.y;
      
      toggleBtn.className = 'sim-toggle-btn state-locked';
      statusText.textContent = 'State: LOCKED (0 Drift • Cursor Frozen)';
      screenBadge.textContent = 'Hardware Locked';
      screenBadge.className = 'pane-badge locked';
      hwBadge.textContent = 'Sensor Disconnected';
      hwBadge.className = 'pane-badge locked';
      driftVal.textContent = '0 px';
      clicksVal.textContent = '0 (blocked)';
      hwSummary.textContent = 'Wiping trackpad freely — zero clicks registered';
    } else {
      toggleBtn.className = 'sim-toggle-btn state-unlocked';
      statusText.textContent = 'State: UNLOCKED (Cursor Drifts)';
      screenBadge.textContent = 'Active Input';
      screenBadge.className = 'pane-badge';
      hwBadge.textContent = 'Hardware Live';
      hwBadge.className = 'pane-badge';
      driftVal.textContent = '±128 px';
      clicksVal.textContent = '14';
      hwSummary.textContent = 'Cloth wiping across trackpad sensor';
    }
  }

  toggleBtn.addEventListener('click', () => {
    setLockedState(!isLocked);
  });

  // Global Keyboard Shortcut Listener for ⌃⌥⌘T
  window.addEventListener('keydown', (e) => {
    // Check for Control + Option + Command + T or Cmd+T inside demo
    if (e.key === 't' || e.key === 'T') {
      if ((e.ctrlKey && e.altKey && e.metaKey) || (e.metaKey && e.altKey)) {
        e.preventDefault();
        setLockedState(!isLocked);
      }
    }
  });

  // Mouse drag support over hardware canvas for manual wiping
  hwCanvas.addEventListener('mousedown', (e) => {
    userIsDragging = true;
    updateCustomWipe(e);
  });
  window.addEventListener('mouseup', () => {
    userIsDragging = false;
  });
  hwCanvas.addEventListener('mousemove', (e) => {
    if (userIsDragging) updateCustomWipe(e);
  });
  hwCanvas.addEventListener('touchstart', (e) => {
    userIsDragging = true;
    if (e.touches[0]) updateCustomTouch(e.touches[0]);
  }, { passive: true });
  hwCanvas.addEventListener('touchmove', (e) => {
    if (userIsDragging && e.touches[0]) updateCustomTouch(e.touches[0]);
  }, { passive: true });
  window.addEventListener('touchend', () => {
    userIsDragging = false;
  });

  function updateCustomWipe(e) {
    const rect = hwCanvas.getBoundingClientRect();
    const scaleX = hwCanvas.width / rect.width;
    const scaleY = hwCanvas.height / rect.height;
    customDragPos.x = (e.clientX - rect.left) * scaleX;
    customDragPos.y = (e.clientY - rect.top) * scaleY;
  }

  function updateCustomTouch(touch) {
    const rect = hwCanvas.getBoundingClientRect();
    const scaleX = hwCanvas.width / rect.width;
    const scaleY = hwCanvas.height / rect.height;
    customDragPos.x = (touch.clientX - rect.left) * scaleX;
    customDragPos.y = (touch.clientY - rect.top) * scaleY;
  }

  // ── Render Loop ────────────────────────────────────────────────────────────
  function animate() {
    time += 0.035;

    // 1. Calculate Wiping Motion across Trackpad
    const padCenter = { x: hwCanvas.width / 2, y: 250 };
    const padRadiusX = 130;
    const padRadiusY = 65;

    if (userIsDragging) {
      targetClothPos.x = customDragPos.x;
      targetClothPos.y = customDragPos.y;
    } else {
      // Natural cleaning swirl (lissajous figure)
      targetClothPos.x = padCenter.x + Math.sin(time * 1.8) * padRadiusX * 0.85 + Math.cos(time * 0.7) * 20;
      targetClothPos.y = padCenter.y + Math.cos(time * 2.3) * padRadiusY * 0.75 + Math.sin(time * 1.2) * 15;
    }

    clothPos.x += (targetClothPos.x - clothPos.x) * 0.18;
    clothPos.y += (targetClothPos.y - clothPos.y) * 0.18;

    // 2. Cursor Behavior
    if (isLocked) {
      // FROZEN IN PLACE (Rock solid)
      cursor.targetX = cursor.lockedX;
      cursor.targetY = cursor.lockedY;
      cursor.x = cursor.lockedX;
      cursor.y = cursor.lockedY;
    } else {
      // DRIFTING WILDLY as cloth wipes
      const deltaX = (clothPos.x - padCenter.x) * 1.6;
      const deltaY = (clothPos.y - padCenter.y) * 1.2;
      cursor.targetX = screenCanvas.width / 2 + deltaX + Math.sin(time * 7) * 25;
      cursor.targetY = screenCanvas.height / 2 + deltaY + Math.cos(time * 5) * 20;

      cursor.x += (cursor.targetX - cursor.x) * 0.22;
      cursor.y += (cursor.targetY - cursor.y) * 0.22;

      // Keep cursor in bounds
      cursor.x = Math.max(20, Math.min(screenCanvas.width - 20, cursor.x));
      cursor.y = Math.max(30, Math.min(screenCanvas.height - 20, cursor.y));

      // Append to movement trail
      cursor.trail.push({ x: cursor.x, y: cursor.y, alpha: 1.0 });
      if (cursor.trail.length > 25) cursor.trail.shift();
    }

    // Decay trails
    cursor.trail.forEach(t => t.alpha *= 0.88);

    // Render both frames
    renderSimulatedScreen();
    renderHardwareTopcase();

    requestAnimationFrame(animate);
  }

  // ── Draw Left Pane: Simulated macOS Desktop ────────────────────────────────
  function renderSimulatedScreen() {
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    const w = screenCanvas.width;
    const h = screenCanvas.height;

    sCtx.clearRect(0, 0, w, h);

    // Desktop wallpaper
    sCtx.fillStyle = isDark ? '#0D1117' : '#F1F3F6';
    sCtx.fillRect(0, 0, w, h);

    // Subtle desktop grid lines
    sCtx.strokeStyle = isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.03)';
    sCtx.lineWidth = 1;
    for (let x = 0; x < w; x += 40) {
      sCtx.beginPath();
      sCtx.moveTo(x, 0);
      sCtx.addLineTo(x, h);
      sCtx.stroke();
    }

    // Top macOS menu bar strip
    sCtx.fillStyle = isDark ? '#161B22' : '#FFFFFF';
    sCtx.fillRect(0, 0, w, 24);
    sCtx.strokeStyle = isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)';
    sCtx.beginPath();
    sCtx.moveTo(0, 24);
    sCtx.addLineTo(w, 24);
    sCtx.stroke();

    // Apple Logo & Menu Bar items
    sCtx.fillStyle = isDark ? '#8B949E' : '#57606A';
    sCtx.font = '10px Inter, sans-serif';
    sCtx.fillText('', 12, 16);
    sCtx.fillText('File', 30, 16);
    sCtx.fillText('Edit', 58, 16);
    sCtx.fillText('View', 86, 16);
    sCtx.fillText('Window', 118, 16);

    // Right menu extras in simulated menu bar
    sCtx.fillText('Trackpad Toggle', w - 110, 16);

    // Draw Mock Application Windows
    mockWindows.forEach((win, idx) => {
      sCtx.save();
      sCtx.shadowColor = 'rgba(0,0,0,0.3)';
      sCtx.shadowBlur = 12;
      sCtx.shadowOffsetY = 4;

      // Window Background
      sCtx.fillStyle = isDark ? win.color : '#FFFFFF';
      sCtx.beginPath();
      sCtx.roundRect(win.x, win.y, win.w, win.h, 8);
      sCtx.fill();
      sCtx.restore();

      // Window Border
      sCtx.strokeStyle = isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.12)';
      sCtx.stroke();

      // Window title bar
      sCtx.fillStyle = isDark ? '#8B949E' : '#656D76';
      sCtx.font = '10px Inter, sans-serif';
      sCtx.fillText(win.title, win.x + 36, win.y + 16);

      // Window pills
      sCtx.fillStyle = '#FF5F56';
      sCtx.beginPath(); sCtx.arc(win.x + 12, win.y + 12, 3.5, 0, Math.PI * 2); sCtx.fill();
      sCtx.fillStyle = '#FFBD2E';
      sCtx.beginPath(); sCtx.arc(win.x + 20, win.y + 12, 3.5, 0, Math.PI * 2); sCtx.fill();

      // Text lines inside window
      sCtx.fillStyle = isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)';
      sCtx.fillRect(win.x + 16, win.y + 36, win.w - 32, 6);
      sCtx.fillRect(win.x + 16, win.y + 50, win.w * 0.7, 6);
      sCtx.fillRect(win.x + 16, win.y + 64, win.w * 0.85, 6);

      // If unlocked and cursor hovers, show accidental selection artifact
      if (!isLocked && cursor.x > win.x && cursor.x < win.x + win.w && cursor.y > win.y && cursor.y < win.y + win.h) {
        sCtx.fillStyle = 'rgba(255, 179, 0, 0.2)';
        sCtx.fillRect(win.x + 16, win.y + 34, win.w - 32, 38);
      }
    });

    // Draw Cursor Drift Trails (when unlocked)
    if (!isLocked && cursor.trail.length > 1) {
      sCtx.beginPath();
      sCtx.moveTo(cursor.trail[0].x, cursor.trail[0].y);
      for (let i = 1; i < cursor.trail.length; i++) {
        sCtx.lineTo(cursor.trail[i].x, cursor.trail[i].y);
      }
      sCtx.strokeStyle = 'rgba(255, 82, 82, 0.35)';
      sCtx.lineWidth = 3;
      sCtx.lineCap = 'round';
      sCtx.stroke();
    }

    // Draw Screen Cursor (macOS arrow cursor)
    sCtx.save();
    sCtx.translate(cursor.x, cursor.y);

    if (isLocked) {
      // LOCKED BADGE HALO
      sCtx.fillStyle = '#00E5FF';
      sCtx.shadowColor = '#00E5FF';
      sCtx.shadowBlur = 16;
      sCtx.beginPath();
      sCtx.arc(0, 0, 9, 0, Math.PI * 2);
      sCtx.fill();

      // Inner lock pad
      sCtx.fillStyle = '#090B0E';
      sCtx.font = 'bold 9px Inter';
      sCtx.textAlign = 'center';
      sCtx.textBaseline = 'middle';
      sCtx.fillText('🔒', 0, 0);

      // Lock status flag tag
      sCtx.shadowBlur = 0;
      sCtx.fillStyle = '#00E5FF';
      sCtx.fillRect(14, -10, 56, 18);
      sCtx.fillStyle = '#000000';
      sCtx.font = 'bold 9px Inter';
      sCtx.textAlign = 'left';
      sCtx.fillText('LOCKED', 18, 3);
    } else {
      // Classic macOS Black Pointer with white border
      sCtx.shadowColor = 'rgba(0,0,0,0.4)';
      sCtx.shadowBlur = 6;
      sCtx.shadowOffsetY = 2;

      sCtx.beginPath();
      sCtx.moveTo(0, 0);
      sCtx.lineTo(0, 16);
      sCtx.lineTo(4, 12);
      sCtx.lineTo(8, 20);
      sCtx.lineTo(11, 19);
      sCtx.lineTo(7, 11);
      sCtx.lineTo(13, 11);
      sCtx.closePath();

      sCtx.fillStyle = '#000000';
      sCtx.fill();
      sCtx.strokeStyle = '#FFFFFF';
      sCtx.lineWidth = 1.5;
      sCtx.stroke();

      // Misclick lightning flash warning if moving fast
      sCtx.shadowBlur = 0;
      sCtx.fillStyle = 'rgba(255, 82, 82, 0.9)';
      sCtx.beginPath();
      sCtx.roundRect(14, -8, 70, 16, 4);
      sCtx.fill();
      sCtx.fillStyle = '#FFFFFF';
      sCtx.font = 'bold 8px Inter';
      sCtx.fillText('DRIFTING ⚠️', 18, 4);
    }

    sCtx.restore();
  }

  // ── Draw Right Pane: MacBook Topcase, Trackpad & Wiping Cloth ──────────────
  function renderHardwareTopcase() {
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    const w = hwCanvas.width;
    const h = hwCanvas.height;

    hCtx.clearRect(0, 0, w, h);

    // Aluminum Topcase Body
    hCtx.fillStyle = isDark ? '#12161E' : '#E6E9EE';
    hCtx.fillRect(0, 0, w, h);

    // Simulated Keyboard Area at top
    const kbX = 60;
    const kbY = 30;
    const kbW = w - 120;
    const kbH = 130;

    // Keyboard well indent
    hCtx.fillStyle = isDark ? '#0A0D12' : '#D2D6DC';
    hCtx.beginPath();
    hCtx.roundRect(kbX, kbY, kbW, kbH, 8);
    hCtx.fill();

    // Keycaps grid
    const cols = 12;
    const rows = 4;
    const keyW = (kbW - 20) / cols;
    const keyH = (kbH - 16) / rows;

    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const kx = kbX + 10 + c * keyW;
        const ky = kbY + 8 + r * keyH;
        hCtx.fillStyle = isDark ? '#1C222B' : '#FFFFFF';
        hCtx.beginPath();
        hCtx.roundRect(kx + 1.5, ky + 1.5, keyW - 3, keyH - 3, 3);
        hCtx.fill();
      }
    }

    // Spacebar
    hCtx.fillStyle = isDark ? '#232A35' : '#F3F4F6';
    hCtx.beginPath();
    hCtx.roundRect(kbX + kbW * 0.32, kbY + kbH - 26, kbW * 0.36, 18, 3);
    hCtx.fill();

    // ── Glass Trackpad Hardware ──────────────────────────────────────────────
    const padX = w / 2 - 150;
    const padY = 190;
    const padW = 300;
    const padH = 150;

    hCtx.save();

    if (isLocked) {
      // ELECTRIC CYAN LOCKOUT GLOW
      hCtx.shadowColor = '#00E5FF';
      hCtx.shadowBlur = 24;
      hCtx.fillStyle = isDark ? '#0B131A' : '#E8F7FF';
      hCtx.beginPath();
      hCtx.roundRect(padX, padY, padW, padH, 12);
      hCtx.fill();

      // Laser boundary line
      hCtx.strokeStyle = '#00E5FF';
      hCtx.lineWidth = 2.5;
      hCtx.stroke();
    } else {
      // Standard matte glass trackpad
      hCtx.shadowColor = 'rgba(0,0,0,0.2)';
      hCtx.shadowBlur = 10;
      hCtx.shadowOffsetY = 3;
      hCtx.fillStyle = isDark ? '#19202B' : '#FFFFFF';
      hCtx.beginPath();
      hCtx.roundRect(padX, padY, padW, padH, 12);
      hCtx.fill();

      hCtx.strokeStyle = isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.12)';
      hCtx.lineWidth = 1;
      hCtx.stroke();
    }

    hCtx.restore();

    // Center divider click tick
    hCtx.strokeStyle = isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)';
    hCtx.lineWidth = 1;
    hCtx.beginPath();
    hCtx.moveTo(w / 2, padY + padH - 12);
    hCtx.addLineTo(w / 2, padY + padH);
    hCtx.stroke();

    // Lock icon watermark in center of trackpad
    hCtx.save();
    hCtx.fillStyle = isLocked ? 'rgba(0, 229, 255, 0.9)' : (isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)');
    hCtx.font = '22px Inter, sans-serif';
    hCtx.textAlign = 'center';
    hCtx.textBaseline = 'middle';
    hCtx.fillText(isLocked ? '🔒 SENSOR LOCKED' : 'TOUCHPAD ACTIVE', w / 2, padY + padH / 2);
    hCtx.restore();

    // ── Microfiber Cleaning Cloth / Wiping Hand ──────────────────────────────
    hCtx.save();
    hCtx.translate(clothPos.x, clothPos.y);

    // Drop shadow under cleaning cloth
    hCtx.shadowColor = 'rgba(0, 0, 0, 0.45)';
    hCtx.shadowBlur = 16;
    hCtx.shadowOffsetY = 8;

    // Cloth Body (Yellow/Cyan microfiber cleaning cloth fold)
    hCtx.fillStyle = isLocked ? '#00E5FF' : '#FFD54F';
    hCtx.beginPath();
    hCtx.roundRect(-42, -42, 84, 84, 18);
    hCtx.fill();

    // Cloth fabric folds / texture
    hCtx.strokeStyle = isLocked ? 'rgba(255,255,255,0.6)' : 'rgba(0,0,0,0.15)';
    hCtx.lineWidth = 2;
    hCtx.beginPath();
    hCtx.arc(0, 0, 24, 0.4, 3.2);
    hCtx.stroke();

    // Label on cloth
    hCtx.fillStyle = isLocked ? '#000000' : '#5D4037';
    hCtx.font = 'bold 9px Inter, sans-serif';
    hCtx.textAlign = 'center';
    hCtx.textBaseline = 'middle';
    hCtx.fillText('WIPING', 0, 0);

    hCtx.restore();
  }

  // Start 60fps loop
  requestAnimationFrame(animate);

  // Expose toggle globally for app.js
  window.setSimulationLocked = setLockedState;
})();
