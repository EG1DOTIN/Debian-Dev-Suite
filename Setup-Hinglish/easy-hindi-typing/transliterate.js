/**
 * Easy Hindi Typing — Offline Phonetic Transliteration Engine
 * Converts Hinglish (Romanized Hindi) to Devanagari script.
 * 100% Offline, Privacy-Focused & Free of External Dependencies.
 */

(function (global) {
  'use strict';

  // Consonant definitions with virama (half-consonant base)
  const CONSONANTS = {
    // Special conjuncts
    'ksh': 'क्ष', 'ksha': 'क्ष',
    'tr': 'त्र',  'tra': 'त्र',
    'gy': 'ज्ञ',  'gya': 'ज्ञ',
    'jny': 'ज्ञ', 'jnya': 'ज्ञ',
    'shr': 'श्र', 'shra': 'श्र',

    // Aspirated and complex consonants
    'kh': 'ख', 'gh': 'घ',
    'chh': 'छ', 'ch': 'च', 'jh': 'झ',
    'thh': 'ठ', 'dhh': 'ढ',
    'th': 'थ', 'dh': 'ध',
    'ph': 'फ', 'bh': 'भ',
    'sh': 'श', 'shh': 'ष',
    'rh': 'ढ़', 'dh_': 'ढ़',

    // Basic consonants
    'k': 'क', 'g': 'ग', 'ng': 'ङ',
    'j': 'ज', 'z': 'ज़', 'za': 'ज़',
    't': 'त', 'd': 'द', 'n': 'न',
    'p': 'प', 'f': 'फ़', 'fa': 'फ़', 'b': 'ब', 'm': 'म',
    'y': 'य', 'r': 'र', 'l': 'ल', 'v': 'व', 'w': 'व',
    's': 'स', 'h': 'ह',
    'T': 'ट', 'D': 'ड', 'N': 'ण', 'R': 'ड़',
    'q': 'क़'
  };

  // Independent vowels (when starting a word or following another vowel)
  const INDEPENDENT_VOWELS = {
    'aa': 'आ', 'a': 'अ',
    'ee': 'ई', 'ii': 'ई', 'i': 'इ',
    'oo': 'ऊ', 'uu': 'ऊ', 'u': 'उ',
    'ri': 'ऋ', 'ree': 'ऋ',
    'ai': 'ऐ', 'e': 'ए',
    'au': 'औ', 'ou': 'औ', 'o': 'ओ',
    'am': 'अं', 'an': 'अं', 'ah': 'अः'
  };

  // Dependent vowel signs (matras applied to consonants)
  const MATRAS = {
    'aa': 'ा', 'a': '',
    'ee': 'ी', 'ii': 'ी', 'i': 'ि',
    'oo': 'ू', 'uu': 'ू', 'u': 'ु',
    'ri': 'ृ', 'ree': 'ृ',
    'ai': 'ै', 'e': 'े',
    'au': 'ौ', 'ou': 'ौ', 'o': 'ो'
  };

  const VIRAMA = '्';
  const ANUSVARA = 'ं';
  const CHANDRABINDU = 'ँ';
  const VISARGA = 'ः';
  const NUKTA = '़';

  /**
   * Phonetic rule-based parser for Roman to Devanagari conversion
   */
  function phoneticConvert(input, opts) {
    if (!input) return '';
    const options = opts || {};
    let text = input.trim().toLowerCase();
    let result = '';
    let i = 0;
    const len = text.length;

    while (i < len) {
      // Check for standalone/starting independent vowels if at start or previous was vowel
      const isStartOrVowelFollower = (i === 0) || (result.length > 0 && isVowelChar(result[result.length - 1]));

      // 1. Try multi-char consonant matches (longest match first)
      let matchedConsonant = null;
      let matchLen = 0;

      const testPatterns = ['shra', 'ksha', 'jnya', 'jny', 'ksh', 'chh', 'shh', 'gya', 'tra', 'dhh', 'thh', 'kh', 'gh', 'ch', 'jh', 'th', 'dh', 'ph', 'bh', 'sh', 'rh', 'ng', 'gy', 'tr', 'za', 'fa', 'k', 'g', 'c', 'j', 'z', 't', 'd', 'n', 'p', 'f', 'b', 'm', 'y', 'r', 'l', 'v', 'w', 's', 'h', 'q'];

      for (const pat of testPatterns) {
        if (text.startsWith(pat, i)) {
          matchedConsonant = CONSONANTS[pat] || (pat === 'c' ? 'क' : null);
          matchLen = pat.length;
          break;
        }
      }

      if (matchedConsonant) {
        i += matchLen;

        // Check if there's a following vowel or anusvara
        let matchedMatra = null;
        let matraLen = 0;

        const matraPatterns = ['ree', 'ri', 'aa', 'ee', 'ii', 'oo', 'uu', 'ai', 'au', 'ou', 'a', 'i', 'u', 'e', 'o'];
        for (const mPat of matraPatterns) {
          if (text.startsWith(mPat, i)) {
            matchedMatra = MATRAS[mPat];
            matraLen = mPat.length;
            break;
          }
        }

        if (matchedMatra !== null) {
          // Consonant + Vowel
          result += matchedConsonant + matchedMatra;
          i += matraLen;

          // Check if anusvara follows (e.g. 'n' at end or before consonant, or 'm' before consonant)
          if (i < len && (text[i] === 'n' || text[i] === 'm')) {
            const nextIdx = i + 1;
            const isEnd = (nextIdx === len);
            const isConsonantFollower = (nextIdx < len && !['a','e','i','o','u'].includes(text[nextIdx]));

            // If 'm' is at the very end of word, in Hindi it is usually 'म' (e.g. 'shyam' -> 'श्याम', 'pratham' -> 'प्रथम')
            if (text[i] === 'm' && isEnd) {
              // Don't treat as anusvara, let the next loop handle 'm' as consonant
            } else if (text[i] === 'n' && (text.endsWith('aan') || text.endsWith('ain') || text.endsWith('on') || text.endsWith('un'))) {
              // Nasalized vowels like 'haan', 'main', 'kyun', 'auron' -> anusvara
              result += ANUSVARA;
              i++;
            } else if (isConsonantFollower) {
              // Before another consonant (e.g. 'hindi', 'mandir', 'champa') -> anusvara
              result += ANUSVARA;
              i++;
            }
          }
        } else {
          // Consonant without explicit vowel
          // If followed by another consonant or end of word:
          if (i < len) {
            // Next is consonant -> use halant (virama)
            result += matchedConsonant + VIRAMA;
          } else {
            // End of word -> standard inherently pronounced consonant (e.g. 'namast' -> 'नमस्ते', 'nam' -> 'नम')
            result += matchedConsonant;
          }
        }
        continue;
      }

      // 2. Try Independent Vowels
      let matchedVowel = null;
      let vowelLen = 0;

      const vowelPatterns = ['ree', 'ri', 'aa', 'ee', 'ii', 'oo', 'uu', 'ai', 'au', 'ou', 'am', 'an', 'ah', 'a', 'i', 'u', 'e', 'o'];
      for (const vPat of vowelPatterns) {
        if (text.startsWith(vPat, i)) {
          matchedVowel = INDEPENDENT_VOWELS[vPat];
          vowelLen = vPat.length;
          break;
        }
      }

      if (matchedVowel) {
        result += matchedVowel;
        i += vowelLen;
        continue;
      }

      // 3. Fallback: punctuation, numbers, spaces, unmapped chars
      result += text[i];
      i++;
    }

    return cleanDevanagari(result);
  }

  function isVowelChar(char) {
    const vowels = 'अआइईउऊऋएऐओऔ';
    return vowels.includes(char);
  }

  function cleanDevanagari(str) {
    // Clean up impossible conjuncts, double viramas, etc.
    return str
      .replace(/््+/g, '्')
      .replace(/्([ \t\n\r])/g, '$1') // remove trailing halant before space
      .replace(/्$/g, '');           // remove trailing halant at end of complete word
  }

  /**
   * Generates suggestions/candidates for a given Roman word
   * @param {string} word - The Roman word typed by the user
   * @returns {Array<string>} - Ranked list of candidates
   */
  function getSuggestions(word) {
    if (!word || !word.trim()) return [];

    const rawWord = word.trim();
    const cleanWord = rawWord.toLowerCase();
    const candidates = [];

    // 1. Direct dictionary match
    if (typeof HINDI_DICTIONARY !== 'undefined' && HINDI_DICTIONARY[cleanWord]) {
      const dictMatches = HINDI_DICTIONARY[cleanWord];
      for (const m of dictMatches) {
        if (!candidates.includes(m)) {
          candidates.push(m);
        }
      }
    }

    // 2. Check dictionary variants (e.g. without trailing 'h', 'n', 'a')
    if (typeof HINDI_DICTIONARY !== 'undefined') {
      const variations = [
        cleanWord + 'a',
        cleanWord.replace(/a$/, ''),
        cleanWord.replace(/n$/, 'an'),
        cleanWord.replace(/ee/g, 'i'),
        cleanWord.replace(/oo/g, 'u'),
        cleanWord.replace(/v/g, 'w'),
        cleanWord.replace(/w/g, 'v'),
        cleanWord.replace(/z/g, 'j'),
        cleanWord.replace(/f/g, 'ph')
      ];

      for (const v of variations) {
        if (HINDI_DICTIONARY[v]) {
          for (const m of HINDI_DICTIONARY[v]) {
            if (!candidates.includes(m) && candidates.length < 5) {
              candidates.push(m);
            }
          }
        }
      }
    }

    // 3. Phonetic Rule-based transliteration
    const phoneticBase = phoneticConvert(cleanWord);
    if (phoneticBase && !candidates.includes(phoneticBase)) {
      candidates.push(phoneticBase);
    }

    // 4. Common phonetic alternatives
    // e.g. Anusvara variations (बिंदु vs चन्द्रबिंदु)
    if (phoneticBase.includes('ं')) {
      const chandra = phoneticBase.replace(/ं/g, 'ँ');
      if (!candidates.includes(chandra) && candidates.length < 5) {
        candidates.push(chandra);
      }
    }

    // Long vs short vowel variations (e.g. ा vs standalone)
    if (cleanWord.endsWith('a') && !phoneticBase.endsWith('ा')) {
      const withAa = phoneticBase + 'ा';
      if (!candidates.includes(withAa) && candidates.length < 5) {
        candidates.push(withAa);
      }
    }

    // 5. Always offer the literal Roman word as an English option (at end)
    if (!candidates.includes(rawWord)) {
      candidates.push(rawWord);
    }

    return candidates.slice(0, 6);
  }

  // Export to global scope
  const EasyHindi = {
    transliterate: phoneticConvert,
    getSuggestions: getSuggestions
  };

  if (typeof window !== 'undefined') {
    window.EasyHindi = EasyHindi;
  }
  if (typeof global !== 'undefined') {
    global.EasyHindi = EasyHindi;
  }
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = EasyHindi;
  }
})(typeof window !== 'undefined' ? window : globalThis);
