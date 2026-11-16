import datetime
import logging
import re

logger = logging.getLogger('freshtrack.ocr.text_parser')

MONTH_MAP = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    'january': 1, 'february': 2, 'march': 3, 'april': 4, 'june': 6,
    'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11, 'december': 12
}

def parse_absolute_date(text: str) -> datetime.date:
    """
    Parses DD/MM/YYYY, DD-MM-YYYY, DD.MM.YYYY, DD MMM YYYY, or MM/YYYY.
    Returns datetime.date or None.
    """
    # 1. Clean and normalize spaces/characters
    text = re.sub(r'[\s\.\-/]+', '-', text.strip())

    # 2. Try DD-MM-YYYY
    match = re.search(r'\b(\d{1,2})-(\d{1,2})-(\d{4})\b', text)
    if match:
        try:
            return datetime.date(int(match.group(3)), int(match.group(2)), int(match.group(1)))
        except ValueError:
            pass

    # 3. Try MM-YYYY (defaulting to first day of month or last day, let's use first day of month)
    match = re.search(r'\b(\d{1,2})-(\d{4})\b', text)
    if match:
        try:
            return datetime.date(int(match.group(2)), int(match.group(1)), 1)
        except ValueError:
            pass

    # 4. Try DD-MMM-YYYY (e.g. 15-JUL-2026 or 15-Jul-2026)
    match = re.search(r'\b(\d{1,2})-([a-zA-Z]{3,9})-(\d{4})\b', text)
    if match:
        mon_str = match.group(2).lower()
        if mon_str in MONTH_MAP:
            try:
                return datetime.date(int(match.group(3)), MONTH_MAP[mon_str], int(match.group(1)))
            except ValueError:
                pass

    # 5. Try MMM-YYYY (e.g. JUL-2026)
    match = re.search(r'\b([a-zA-Z]{3,9})-(\d{4})\b', text)
    if match:
        mon_str = match.group(1).lower()
        if mon_str in MONTH_MAP:
            try:
                return datetime.date(int(match.group(2)), MONTH_MAP[mon_str], 1)
            except ValueError:
                pass

    return None

class OCRDateParser:
    @staticmethod
    def extract_dates(text: str) -> dict:
        """
        Scans OCR raw text for expiry dates, manufacturing dates, packing dates,
        and relative best-before calculations.

        Returns a dict:
        {
            "expiry_date": date or None,
            "manufacturing_date": date or None,
            "packed_date": date or None,
            "best_before_date": date or None,
            "date_type": str,
            "date_source": str,
            "date_confidence": str,
            "raw_date_text": str,
            "derivation_steps": str or None
        }
        """
        lines = [line.strip() for line in text.split('\n') if line.strip()]

        mfg_date = None
        pkd_date = None
        exp_date = None
        bb_date = None

        raw_mfg_text = ""
        raw_pkd_text = ""
        raw_exp_text = ""

        # Regex search patterns
        mfg_pattern = re.compile(r'\b(mfg|mfd|mfg\s*date|mfd\s*date|manufacturing|manufactured)\b', re.IGNORECASE)
        pkd_pattern = re.compile(r'\b(pkd|packed|packed\s*on|packing|pkg)\b', re.IGNORECASE)
        exp_pattern = re.compile(r'\b(exp|use\s*by|expiry|expiry\s*date|best\s*before|use\s*before)\b', re.IGNORECASE)

        # Find dates on lines or surrounding lines
        for i, line in enumerate(lines):
            # Check Mfg
            if mfg_pattern.search(line):
                parsed = parse_absolute_date(line)
                if parsed:
                    mfg_date = parsed
                    raw_mfg_text = line
                elif i + 1 < len(lines):
                    parsed = parse_absolute_date(lines[i+1])
                    if parsed:
                        mfg_date = parsed
                        raw_mfg_text = f"{line} {lines[i+1]}"

            # Check Pkd
            if pkd_pattern.search(line):
                parsed = parse_absolute_date(line)
                if parsed:
                    pkd_date = parsed
                    raw_pkd_text = line
                elif i + 1 < len(lines):
                    parsed = parse_absolute_date(lines[i+1])
                    if parsed:
                        pkd_date = parsed
                        raw_pkd_text = f"{line} {lines[i+1]}"

            # Check Exp/Use By
            if exp_pattern.search(line):
                parsed = parse_absolute_date(line)
                if parsed:
                    # Distinguish EXP from BEST BEFORE
                    if "best" in line.lower() or "bb" in line.lower():
                        bb_date = parsed
                    else:
                        exp_date = parsed
                    raw_exp_text = line
                elif i + 1 < len(lines):
                    parsed = parse_absolute_date(lines[i+1])
                    if parsed:
                        if "best" in line.lower() or "bb" in line.lower():
                            bb_date = parsed
                        else:
                            exp_date = parsed
                        raw_exp_text = f"{line} {lines[i+1]}"

        # Resolve Packed Date vs Mfg Date (often interchangeable in calculations)
        reference_date = pkd_date or mfg_date
        derivation = None
        source = "unknown"
        confidence = "Low"
        date_type = "unknown"
        raw_txt = ""

        # Relative Expiry Calculation (e.g., "BEST BEFORE 6 MONTHS FROM PACKING")
        if reference_date:
            duration_match = re.search(r'best\s*before\s*(\d+)\s*(month|months|day|days)\b', text, re.IGNORECASE)
            if duration_match:
                amount = int(duration_match.group(1))
                unit = duration_match.group(2).lower()

                if "month" in unit:
                    # Calculate new date by shifting months
                    # We can use simple 30 days shift or datetime calculation
                    exp_calculated = reference_date + datetime.timedelta(days=amount * 30)
                else:
                    exp_calculated = reference_date + datetime.timedelta(days=amount)

                exp_date = exp_calculated
                bb_date = exp_calculated
                source = "calculated_from_packaging"
                confidence = "High"
                date_type = "best_before"
                raw_txt = f"{raw_pkd_text or raw_mfg_text} | {duration_match.group(0)}"
                derivation = f"Calculated as {amount} {unit}s from packaging/mfg date of {reference_date.isoformat()}"

        if exp_date and source == "unknown":
            source = "ocr_verified"
            confidence = "High"
            date_type = "use_by"
            raw_txt = raw_exp_text
        elif bb_date and source == "unknown":
            source = "ocr_verified"
            confidence = "High"
            date_type = "best_before"
            raw_txt = raw_exp_text

        return {
            "expiry_date": exp_date,
            "manufacturing_date": mfg_date,
            "packed_date": pkd_date,
            "best_before_date": bb_date,
            "date_type": date_type,
            "date_source": source,
            "date_confidence": confidence,
            "raw_date_text": raw_txt,
            "derivation_steps": derivation
        }
