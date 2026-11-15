"""
Universal Date & Timestamp Parser for Google Takeout and Chat Exports.
Supports ISO-8601, localized month names (EN, FR, DE, ES, IT), 12/24-hour clocks,
and provides component-level fallback parsing.
"""

import re
from datetime import datetime
from typing import Optional, Any

# Multi-language month names
MONTH_MAP = {
    # English
    "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
    "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
    "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10,
    "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12,
    # French
    "janv": 1, "févr": 2, "fevr": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6,
    "juil": 7, "août": 8, "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11, "décembre": 12,
    # German
    "jän": 1, "januar": 1, "februar": 2, "märz": 3, "maerz": 3, "mai": 5,
    "juni": 6, "juli": 7, "oktober": 10, "dezember": 12,
    # Spanish
    "enero": 1, "febrero": 2, "marzo": 3, "mayo": 5, "junio": 6, "julio": 7,
    "agosto": 8, "septiembre": 9, "octubre": 10, "noviembre": 11, "diciembre": 12,
    # Italian
    "gennaio": 1, "febbraio": 2, "aprile": 4, "maggio": 5, "giugno": 6,
    "luglio": 7, "settembre": 9, "ottobre": 10, "dicembre": 12
}

MONTHS = (
    r'(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|'
    r'Jul(?:y)?|Aug(?:ust)?|Sep(?:t|tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?|'
    r'janv(?:\.|ier)?|f[ée]vr(?:\.|ier)?|mars|avril|mai|juin|juil(?:\.|let)?|ao[ûu]t|septembre|octobre|novembre|d[ée]cembre|'
    r'j[äa]n(?:uar)?|februar|m[äa]rz|juni|juli|oktober|dezember|'
    r'enero|febrero|marzo|mayo|junio|julio|agosto|diciembre|'
    r'gennaio|febbraio|aprile|maggio|giugno|luglio|settembre|ottobre)'
)

DATE_PATTERN = re.compile(
    r'('
    r'(?:'
    rf'(?:\d{{1,2}}\s+{MONTHS}\s+\d{{4}})'      # 31 Aug 2026 or 17 Sept 2026
    r'|'
    rf'(?:{MONTHS}\s+\d{{1,2}},?\s+\d{{4}})'    # Nov 11, 2026 or November 11 2026
    r'|'
    r'(?:\d{4}[-/.]\d{1,2}[-/.]\d{1,2})'       # 2026-08-31
    r'|'
    r'(?:\d{1,2}[-/.]\d{1,2}[-/.]\d{4})'       # 31/08/2026 or 31.08.2026
    r')'
    r'[, ]+\d{1,2}:\d{2}(?::\d{2})?'           # time: 21:28:40 or 7:34:20
    r'(?:[\s\u202f]*(?:AM|PM|am|pm))?'         # optional AM/PM
    r'(?:[\s\u202f]*[A-Z]{2,5})?'              # optional timezone like IST, UTC, GMT, EST
    r')',
    re.IGNORECASE,
)


def describe_date_format(sample_date_str: str) -> str:
    """Inspects a sample Takeout date string and describes its format for the user."""
    if not sample_date_str:
        return "Unknown"
    s = sample_date_str.strip()
    has_ampm = bool(re.search(r"\b(?:AM|PM)\b", s, re.IGNORECASE))
    clock = "12-hour AM/PM" if has_ampm else "24-hour"

    tz_match = re.search(r"\b([A-Z]{2,5}|[+-]\d{2}:?\d{2})$", s)
    tz = f" [{tz_match.group(1)}]" if tz_match else ""

    if re.search(r"^\d{1,2}\s+[A-Za-z]+", s):
        return f"Day-first with month name ({clock}){tz}"
    elif re.search(r"^[A-Za-z]+\s+\d{1,2}", s):
        return f"Month-first with month name ({clock}){tz}"
    elif re.search(r"^\d{4}[-/.]\d{1,2}[-/.]\d{1,2}", s):
        return f"ISO / Year-first ({clock}){tz}"
    elif re.search(r"^\d{1,2}[-/.]\d{1,2}[-/.]\d{4}", s):
        return f"Numeric Day/Month/Year ({clock}){tz}"
    return f"Takeout format ({clock}){tz}"


def parse_iso_or_text_time(time_str: Optional[Any] = None) -> float:
    """
    Universally parses any ISO timestamp, localized Google Takeout date,
    or human date format into Unix timestamp epoch seconds.
    Supports English, French, German, Spanish, Italian, numeric (DD/MM, MM/DD),
    12-hour AM/PM and 24-hour formats with component fallback.
    """
    if not time_str:
        return datetime.now().timestamp()

    clean = re.sub(r"[\u202f\xa0\.]", " ", str(time_str)).strip()
    clean_norm = re.sub(r"\bSept\b", "Sep", clean, flags=re.IGNORECASE)
    clean_no_tz = re.sub(r"\s+(?:[A-Z]{2,5}|[+-]\d{2}:?\d{2})$", "", clean_norm).strip()

    fmts = [
        "%b %d, %Y, %I:%M:%S %p",
        "%B %d, %Y, %I:%M:%S %p",
        "%b %d, %Y, %H:%M:%S",
        "%B %d, %Y, %H:%M:%S",
        "%d %b %Y, %H:%M:%S",
        "%d %B %Y, %H:%M:%S",
        "%d %b %Y, %I:%M:%S %p",
        "%d %B %Y, %I:%M:%S %p",
        "%d %b %Y %H:%M:%S",
        "%d %B %Y %H:%M:%S",
        "%b %d %Y, %H:%M:%S",
        "%b %d %Y %H:%M:%S",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%d/%m/%Y, %H:%M:%S",
        "%d/%m/%Y %H:%M:%S",
        "%m/%d/%Y, %I:%M:%S %p",
        "%m/%d/%Y %H:%M:%S",
        "%Y/%m/%d %H:%M:%S",
        "%d %b %Y, %H:%M",
        "%d %B %Y, %H:%M",
        "%b %d, %Y, %I:%M %p",
        "%b %d, %Y, %H:%M",
        "%d %m %Y %H:%M:%S",
    ]
    for fmt in fmts:
        try:
            return datetime.strptime(clean_no_tz, fmt).timestamp()
        except Exception:
            continue

    try:
        clean_iso = clean.replace("Z", "+00:00")
        return datetime.fromisoformat(clean_iso).timestamp()
    except Exception:
        pass

    # Universal Component Extractor Fallback
    try:
        y_match = re.search(r"\b(20\d{2}|19\d{2})\b", clean)
        year = int(y_match.group(1)) if y_match else datetime.now().year

        t_match = re.search(r"\b(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*(AM|PM|am|pm))?\b", clean)
        if t_match:
            hour = int(t_match.group(1))
            minute = int(t_match.group(2))
            second = int(t_match.group(3)) if t_match.group(3) else 0
            ampm = t_match.group(4)
            if ampm:
                if ampm.upper() == "PM" and hour < 12:
                    hour += 12
                elif ampm.upper() == "AM" and hour == 12:
                    hour = 0
        else:
            hour, minute, second = 0, 0, 0

        month = None
        for word in re.findall(r"[A-Za-z\u00C0-\u017F]+", clean):
            w_low = word.lower()
            if w_low in MONTH_MAP:
                month = MONTH_MAP[w_low]
                break

        numbers = [int(n) for n in re.findall(r"\b\d{1,2}\b", clean)]
        time_nums = [int(t_match.group(1)), int(t_match.group(2))] if t_match else []
        if t_match and t_match.group(3):
            time_nums.append(int(t_match.group(3)))

        cand_days = []
        for n in numbers:
            if 1 <= n <= 31 and n not in time_nums:
                cand_days.append(n)

        if month is not None:
            day = cand_days[0] if cand_days else 1
        elif len(cand_days) >= 2:
            if cand_days[0] > 12:
                day, month = cand_days[0], cand_days[1]
            elif cand_days[1] > 12:
                month, day = cand_days[0], cand_days[1]
            else:
                day, month = cand_days[0], cand_days[1]
        else:
            day = cand_days[0] if cand_days else 1
            month = 1

        dt = datetime(year, month, day, hour, minute, second)
        return dt.timestamp()
    except Exception:
        return datetime.now().timestamp()

