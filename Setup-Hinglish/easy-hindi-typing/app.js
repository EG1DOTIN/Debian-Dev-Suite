/**
 * Easy Hindi Typing — Frontend Controller & Caret Tracking Engine
 * Part of Debian Dev Suite (100% Offline, Privacy-Focused)
 */

(function () {
  'use strict';

  // DOM Elements
  const editor = document.getElementById('editorArea');
  const caretMirror = document.getElementById('caretMirror');
  const suggestionsBox = document.getElementById('suggestionsBox');
  const suggestionsList = document.getElementById('suggestionsList');
  const copyBtn = document.getElementById('copyBtn');
  const downloadBtn = document.getElementById('downloadBtn');
  const clearBtn = document.getElementById('clearBtn');
  const decreaseFontBtn = document.getElementById('decreaseFontBtn');
  const increaseFontBtn = document.getElementById('increaseFontBtn');
  const currentFontSizeSpan = document.getElementById('currentFontSize');
  const wordCountSpan = document.getElementById('wordCount');
  const charCountSpan = document.getElementById('charCount');
  const toastNotification = document.getElementById('toastNotification');
  const toastMessage = document.getElementById('toastMessage');
  const themeToggleBtn = document.getElementById('themeToggleBtn');
  const moonIcon = document.getElementById('moonIcon');
  const sunIcon = document.getElementById('sunIcon');
  const toggleKeyboardBtn = document.getElementById('toggleKeyboardBtn');
  const virtualKeyboardSection = document.getElementById('virtualKeyboardSection');
  const closeVkBtn = document.getElementById('closeVkBtn');
  const vkKeyboard = document.getElementById('vkKeyboard');
  const symbolsBar = document.getElementById('symbolsBar');
  const helpBtn = document.getElementById('helpBtn');
  const helpModal = document.getElementById('helpModal');
  const closeHelpModalBtn = document.getElementById('closeHelpModalBtn');

  // State
  let currentCandidates = [];
  let selectedCandidateIndex = 0;
  let activeWord = '';
  let activeWordStart = -1;
  let currentFontSize = 20;
  let toastTimer = null;

  // Initialize App
  function init() {
    loadSavedSettings();
    initTheme();
    initVirtualKeyboard();
    bindEvents();
    syncMirrorStyles();
    updateStats();
    editor.focus();
  }

  // Bind Event Listeners
  function bindEvents() {
    // Editor Typing & Navigation
    editor.addEventListener('input', handleEditorInput);
    editor.addEventListener('keydown', handleEditorKeyDown);
    editor.addEventListener('click', handleEditorCursorMove);
    editor.addEventListener('keyup', handleEditorKeyUp);
    editor.addEventListener('scroll', updateSuggestionsPosition);

    // Toolbar Buttons
    copyBtn.addEventListener('click', copyToClipboard);
    downloadBtn.addEventListener('click', downloadAsTextFile);
    clearBtn.addEventListener('click', clearEditorText);

    decreaseFontBtn.addEventListener('click', () => changeFontSize(-2));
    increaseFontBtn.addEventListener('click', () => changeFontSize(+2));

    themeToggleBtn.addEventListener('click', toggleTheme);
    toggleKeyboardBtn.addEventListener('click', toggleVirtualKeyboard);
    closeVkBtn.addEventListener('click', () => virtualKeyboardSection.classList.add('hidden'));

    helpBtn.addEventListener('click', () => helpModal.classList.remove('hidden'));
    closeHelpModalBtn.addEventListener('click', () => helpModal.classList.add('hidden'));
    helpModal.addEventListener('click', (e) => {
      if (e.target === helpModal) helpModal.classList.add('hidden');
    });

    // Quick Symbols Click
    symbolsBar.addEventListener('click', (e) => {
      const btn = e.target.closest('.symbol-btn');
      if (!btn) return;
      const symbol = btn.getAttribute('data-sym');
      if (symbol) {
        insertTextAtCursor(symbol);
        editor.focus();
      }
    });

    // Window Resize -> Recompute Mirror & Box
    window.addEventListener('resize', () => {
      syncMirrorStyles();
      if (!suggestionsBox.classList.contains('hidden')) {
        updateSuggestionsPosition();
      }
    });

    // Hide suggestions on outside click
    document.addEventListener('click', (e) => {
      if (!e.target.closest('.textarea-wrapper')) {
        hideSuggestions();
      }
    });
  }

  // Synchronize CSS properties between textarea and mirror div
  function syncMirrorStyles() {
    const computed = window.getComputedStyle(editor);
    const propertiesToCopy = [
      'boxSizing', 'width', 'fontFamily', 'fontSize', 'fontWeight',
      'lineHeight', 'letterSpacing', 'wordSpacing', 'paddingTop',
      'paddingRight', 'paddingBottom', 'paddingLeft', 'borderTopWidth',
      'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth', 'whiteSpace'
    ];

    propertiesToCopy.forEach((prop) => {
      caretMirror.style[prop] = computed[prop];
    });
  }

  // Calculate pixel coordinates of cursor
  function getCaretCoordinates() {
    syncMirrorStyles();
    const text = editor.value;
    const caretPos = editor.selectionStart;

    const beforeCaret = text.substring(0, caretPos);
    const afterCaret = text.substring(caretPos);

    // Clear mirror
    caretMirror.innerHTML = '';

    // Create text node for before caret
    const beforeNode = document.createTextNode(beforeCaret);
    caretMirror.appendChild(beforeNode);

    // Create marker span
    const marker = document.createElement('span');
    marker.textContent = '|';
    caretMirror.appendChild(marker);

    // Create text node for remainder
    const afterNode = document.createTextNode(afterCaret);
    caretMirror.appendChild(afterNode);

    const markerRect = marker.getBoundingClientRect();
    const mirrorRect = caretMirror.getBoundingClientRect();
    const textareaRect = editor.getBoundingClientRect();

    const lineHeight = parseFloat(window.getComputedStyle(editor).lineHeight) || (currentFontSize * 1.5);

    // Relative to editor top-left
    let left = markerRect.left - mirrorRect.left;
    let top = (markerRect.top - mirrorRect.top) - editor.scrollTop + lineHeight + 4;

    // Bounds check within editor width
    const maxWidth = editor.clientWidth - 260;
    if (left > maxWidth) {
      left = Math.max(10, maxWidth);
    }
    if (left < 10) left = 10;

    return { top, left };
  }

  // Handle Input in Textarea
  function handleEditorInput() {
    updateStats();
    saveDraft();

    const cursorPos = editor.selectionStart;
    const text = editor.value;

    // Find the word immediately preceding the cursor
    const textBeforeCaret = text.substring(0, cursorPos);
    const match = textBeforeCaret.match(/([a-zA-Z0-9]+)$/);

    if (match) {
      activeWord = match[1];
      activeWordStart = cursorPos - activeWord.length;

      // Generate suggestions
      if (typeof EasyHindi !== 'undefined' && EasyHindi.getSuggestions) {
        currentCandidates = EasyHindi.getSuggestions(activeWord);
      } else {
        currentCandidates = [activeWord];
      }

      if (currentCandidates.length > 0) {
        selectedCandidateIndex = 0;
        renderSuggestions();
        updateSuggestionsPosition();
        showSuggestions();
      } else {
        hideSuggestions();
      }
    } else {
      hideSuggestions();
    }
  }

  // Key Down Events (Space, Enter, 1-9, Arrows, Escape)
  function handleEditorKeyDown(e) {
    const isShowing = !suggestionsBox.classList.contains('hidden');

    if (isShowing && currentCandidates.length > 0) {
      // 1. Commit top or selected candidate on Space
      if (e.key === ' ' || e.code === 'Space') {
        e.preventDefault();
        commitCandidate(currentCandidates[selectedCandidateIndex], true);
        return;
      }

      // 2. Commit on Enter
      if (e.key === 'Enter') {
        e.preventDefault();
        commitCandidate(currentCandidates[selectedCandidateIndex], false);
        return;
      }

      // 3. Digit Keys 1-9
      if (/^[1-9]$/.test(e.key)) {
        const index = parseInt(e.key, 10) - 1;
        if (index < currentCandidates.length) {
          e.preventDefault();
          commitCandidate(currentCandidates[index], true);
          return;
        }
      }

      // 4. Arrow Down
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        selectedCandidateIndex = (selectedCandidateIndex + 1) % currentCandidates.length;
        highlightCandidate();
        return;
      }

      // 5. Arrow Up
      if (e.key === 'ArrowUp') {
        e.preventDefault();
        selectedCandidateIndex = (selectedCandidateIndex - 1 + currentCandidates.length) % currentCandidates.length;
        highlightCandidate();
        return;
      }

      // 6. Escape -> Dismiss suggestions and keep English word
      if (e.key === 'Escape') {
        e.preventDefault();
        hideSuggestions();
        return;
      }

      // 7. Tab -> Commit candidate + space
      if (e.key === 'Tab') {
        e.preventDefault();
        commitCandidate(currentCandidates[selectedCandidateIndex], true);
        return;
      }
    }
  }

  function handleEditorKeyUp(e) {
    if (['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(e.key)) {
      handleEditorCursorMove();
    }
  }

  function handleEditorCursorMove() {
    const cursorPos = editor.selectionStart;
    const text = editor.value;
    const textBeforeCaret = text.substring(0, cursorPos);
    const match = textBeforeCaret.match(/([a-zA-Z0-9]+)$/);

    if (match) {
      activeWord = match[1];
      activeWordStart = cursorPos - activeWord.length;
      if (typeof EasyHindi !== 'undefined' && EasyHindi.getSuggestions) {
        currentCandidates = EasyHindi.getSuggestions(activeWord);
      }
      if (currentCandidates.length > 0) {
        selectedCandidateIndex = 0;
        renderSuggestions();
        updateSuggestionsPosition();
        showSuggestions();
      }
    } else {
      hideSuggestions();
    }
  }

  // Position Suggestions Box
  function updateSuggestionsPosition() {
    if (suggestionsBox.classList.contains('hidden')) return;
    const coords = getCaretCoordinates();
    suggestionsBox.style.top = coords.top + 'px';
    suggestionsBox.style.left = coords.left + 'px';
  }

  // Render Candidate Items in Popup
  function renderSuggestions() {
    suggestionsList.innerHTML = '';
    currentCandidates.forEach((cand, idx) => {
      const li = document.createElement('li');
      li.className = 'suggestion-item' + (idx === selectedCandidateIndex ? ' active' : '');
      li.setAttribute('role', 'option');
      li.setAttribute('data-index', idx);

      const wordSpan = document.createElement('span');
      wordSpan.className = 'cand-word';
      wordSpan.textContent = cand;

      const numSpan = document.createElement('span');
      numSpan.className = 'cand-number';
      numSpan.textContent = (idx + 1);

      li.appendChild(wordSpan);
      li.appendChild(numSpan);

      // Click to choose
      li.addEventListener('mousedown', (e) => {
        e.preventDefault();
        commitCandidate(cand, true);
      });

      suggestionsList.appendChild(li);
    });
  }

  // Highlight Candidate Item
  function highlightCandidate() {
    const items = suggestionsList.querySelectorAll('.suggestion-item');
    items.forEach((item, idx) => {
      if (idx === selectedCandidateIndex) {
        item.classList.add('active');
        item.scrollIntoView({ block: 'nearest' });
      } else {
        item.classList.remove('active');
      }
    });
  }

  // Commit Candidate into Textarea
  function commitCandidate(candidateWord, addSpace) {
    if (activeWordStart < 0) return;

    const text = editor.value;
    const wordEnd = activeWordStart + activeWord.length;

    const before = text.substring(0, activeWordStart);
    const after = text.substring(wordEnd);
    const insertion = candidateWord + (addSpace ? ' ' : '');

    editor.value = before + insertion + after;

    const newCursorPos = activeWordStart + insertion.length;
    editor.selectionStart = newCursorPos;
    editor.selectionEnd = newCursorPos;

    hideSuggestions();
    updateStats();
    saveDraft();
    editor.focus();
  }

  function showSuggestions() {
    suggestionsBox.classList.remove('hidden');
  }

  function hideSuggestions() {
    suggestionsBox.classList.add('hidden');
    currentCandidates = [];
    activeWord = '';
    activeWordStart = -1;
  }

  // Insert Text at Cursor (for virtual keyboard & symbol bar)
  function insertTextAtCursor(textToInsert) {
    const start = editor.selectionStart;
    const end = editor.selectionEnd;
    const text = editor.value;

    editor.value = text.substring(0, start) + textToInsert + text.substring(end);
    const newPos = start + textToInsert.length;
    editor.selectionStart = newPos;
    editor.selectionEnd = newPos;

    updateStats();
    saveDraft();
  }

  // Word and Character Counter
  function updateStats() {
    const text = editor.value.trim();
    const words = text ? text.split(/\s+/).filter(Boolean).length : 0;
    const chars = editor.value.length;

    wordCountSpan.textContent = words + ' शब्द';
    charCountSpan.textContent = chars + ' अक्षर';
  }

  // Copy to Clipboard
  function copyToClipboard() {
    const text = editor.value;
    if (!text) {
      showToast('कॉपी करने के लिए कुछ टाइप करें!');
      return;
    }

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(() => {
        showToast('सफलतापूर्वक कॉपी किया गया! (Copied)');
      }).catch(() => {
        fallbackCopy();
      });
    } else {
      fallbackCopy();
    }
  }

  function fallbackCopy() {
    editor.select();
    try {
      document.execCommand('copy');
      showToast('सफलतापूर्वक कॉपी किया गया! (Copied)');
    } catch (err) {
      showToast('कॉपी करने में विफल');
    }
  }

  // Download as UTF-8 .txt File
  function downloadAsTextFile() {
    const text = editor.value;
    if (!text) {
      showToast('डाउनलोड करने के लिए पहले कुछ टाइप करें!');
      return;
    }

    const blob = new Blob([text], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const now = new Date();
    const dateStr = now.toISOString().slice(0, 10);
    const a = document.createElement('a');
    a.href = url;
    a.download = `EasyHindiTyping_${dateStr}.txt`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    showToast('फ़ाइल डाउनलोड हो गई!');
  }

  // Clear Editor
  function clearEditorText() {
    if (!editor.value) return;
    if (confirm('क्या आप पूरा टेक्स्ट साफ़ करना चाहते हैं? (Clear all text?)')) {
      editor.value = '';
      hideSuggestions();
      updateStats();
      saveDraft();
      editor.focus();
      showToast('टेक्स्ट साफ़ कर दिया गया');
    }
  }

  // Font Size
  function changeFontSize(delta) {
    currentFontSize = Math.max(14, Math.min(36, currentFontSize + delta));
    editor.style.fontSize = currentFontSize + 'px';
    currentFontSizeSpan.textContent = currentFontSize + 'px';
    localStorage.setItem('easyHindiFontSize', currentFontSize);
    syncMirrorStyles();
  }

  // Theme Management
  function initTheme() {
    const savedTheme = localStorage.getItem('easyHindiTheme') || 'dark';
    setTheme(savedTheme);
  }

  function toggleTheme() {
    const currentTheme = document.documentElement.getAttribute('data-theme') || 'dark';
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
    setTheme(newTheme);
  }

  function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('easyHindiTheme', theme);
    if (theme === 'dark') {
      moonIcon.classList.remove('hidden');
      sunIcon.classList.add('hidden');
    } else {
      moonIcon.classList.add('hidden');
      sunIcon.classList.remove('hidden');
    }
  }

  // Toast Notification
  function showToast(msg) {
    toastMessage.textContent = msg;
    toastNotification.classList.remove('hidden');
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      toastNotification.classList.add('hidden');
    }, 2500);
  }

  // Virtual Keyboard
  function initVirtualKeyboard() {
    const rows = [
      ['अ', 'आ', 'इ', 'ई', 'उ', 'ऊ', 'ए', 'ऐ', 'ओ', 'औ', 'ऋ', 'अं', 'अः'],
      ['ा', 'ि', 'ी', 'ु', 'ू', 'े', 'ै', 'ो', 'ौ', 'ृ', 'ं', 'ँ', 'ः', '्'],
      ['क', 'ख', 'ग', 'घ', 'ङ', 'च', 'छ', 'ज', 'झ', 'ञ'],
      ['ट', 'ठ', 'ड', 'ढ', 'ण', 'त', 'थ', 'द', 'ध', 'न'],
      ['प', 'फ', 'ब', 'भ', 'म', 'य', 'र', 'ल', 'व', 'श', 'ष', 'स', 'ह'],
      ['क्ष', 'त्र', 'ज्ञ', 'श्र', 'ड़', 'ढ़', 'ज़', 'फ़', '।', '॥', 'ॐ', '₹']
    ];

    vkKeyboard.innerHTML = '';
    rows.forEach((row) => {
      const rowDiv = document.createElement('div');
      rowDiv.className = 'vk-row';
      row.forEach((char) => {
        const btn = document.createElement('button');
        btn.className = 'vk-key';
        btn.textContent = char;
        btn.type = 'button';
        btn.addEventListener('click', () => {
          insertTextAtCursor(char);
          editor.focus();
        });
        rowDiv.appendChild(btn);
      });
      vkKeyboard.appendChild(rowDiv);
    });
  }

  function toggleVirtualKeyboard() {
    virtualKeyboardSection.classList.toggle('hidden');
    if (!virtualKeyboardSection.classList.contains('hidden')) {
      virtualKeyboardSection.scrollIntoView({ behavior: 'smooth' });
    }
  }

  // Local Storage Save/Restore
  function saveDraft() {
    localStorage.setItem('easyHindiDraft', editor.value);
  }

  function loadSavedSettings() {
    const savedDraft = localStorage.getItem('easyHindiDraft');
    if (savedDraft) {
      editor.value = savedDraft;
    }

    const savedFontSize = localStorage.getItem('easyHindiFontSize');
    if (savedFontSize) {
      currentFontSize = parseInt(savedFontSize, 10);
      editor.style.fontSize = currentFontSize + 'px';
      currentFontSizeSpan.textContent = currentFontSize + 'px';
    }
  }

  // Start
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
