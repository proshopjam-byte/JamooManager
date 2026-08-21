from __future__ import annotations

import base64
import json
import re
import sys
import unicodedata
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from html import unescape
from html.parser import HTMLParser
from pathlib import Path
from typing import Any


SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"]
ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "output" / "portal_emails_latest.json"
QUERY = (
    "{from:sales@mail.travel.rakuten.co.jp "
    "from:jalan-yoyakutsutsi@r.recruit.co.jp} after:2026/01/01"
)


class _HtmlTextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() in {"br", "p", "div", "li", "tr", "h1", "h2", "h3"}:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() in {"p", "div", "li", "tr"}:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        self.parts.append(data)

    def text(self) -> str:
        return unescape("".join(self.parts))


def normalize_text(value: str) -> str:
    value = unicodedata.normalize("NFKC", value or "")
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    value = value.replace("\u3000", " ")
    lines = [re.sub(r"[ \t]+", " ", line).strip() for line in value.split("\n")]
    return "\n".join(lines)


def _field(text: str, label: str) -> str | None:
    match = re.search(
        rf"(?m)^\s*{label}\s*[:：]\s*(.*?)\s*$",
        text,
        re.IGNORECASE,
    )
    if not match:
        return None
    value = match.group(1).strip()
    return value if value and value != "-" else None


def _money(value: str | None) -> int | None:
    if not value:
        return None
    match = re.search(r"-?[\d,]+", value)
    return int(match.group(0).replace(",", "")) if match else None


def _number(text: str | None, pattern: str) -> int:
    if not text:
        return 0
    match = re.search(pattern, text, re.IGNORECASE)
    return int(match.group(1)) if match else 0


def _iso_date(year: str, month: str, day: str) -> str:
    return f"{int(year):04d}-{int(month):02d}-{int(day):02d}"


def _date_time(value: str | None) -> tuple[str | None, str | None]:
    if not value:
        return None, None
    normalized = normalize_text(value)
    match = re.search(
        r"(\d{4})\s*[-/年]\s*(\d{1,2})\s*[-/月]\s*(\d{1,2})\s*日?",
        normalized,
    )
    if not match:
        return None, None
    date = _iso_date(*match.groups())
    time_match = re.search(r"(?:\s|日|\))([01]?\d|2[0-3]):([0-5]\d)", normalized)
    time = f"{int(time_match.group(1)):02d}:{time_match.group(2)}" if time_match else None
    return date, time


def _add_days(date_text: str | None, days: int) -> str | None:
    if not date_text:
        return None
    return (datetime.strptime(date_text, "%Y-%m-%d") + timedelta(days=days)).strftime(
        "%Y-%m-%d"
    )


def _meal_flags(
    plan_name: str | None,
    meal_text: str | None = None,
) -> tuple[bool | None, bool | None]:
    combined = normalize_text(f"{plan_name or ''} {meal_text or ''}").lower()
    if not combined.strip():
        return None, None
    has_meal_information = bool(
        re.search(
            r"素泊|食事なし|朝食|夕食|朝あり|夕あり|朝なし|夕なし|2食|二食|朝夕",
            combined,
        )
    )
    if not has_meal_information:
        return None, None
    breakfast = bool(
        re.search(r"朝食|朝あり|1泊朝食|2食|二食|朝夕", combined)
    ) and "朝なし" not in combined
    dinner = bool(
        re.search(r"夕食|夕あり|2食|二食|朝夕", combined)
    ) and "夕なし" not in combined
    return breakfast, dinner


def _event_type(subject: str, source: str) -> str:
    normalized = normalize_text(subject).lower()
    if "キャンセル" in normalized or "cxl" in normalized:
        return "cancelled"
    if any(word in normalized for word in ("変更", "日程短縮", "日程延長", "chg")):
        return "changed"
    return "newReservation"


def parse_rakuten(subject: str, body: str) -> dict[str, Any]:
    text = normalize_text(body)
    event_type = _event_type(subject, "Rakuten Travel")
    details = text
    if "■ 日程短縮後" in text:
        details = text.split("■ 日程短縮後", 1)[1]
    elif "■ 日程延長後" in text:
        details = text.split("■ 日程延長後", 1)[1]

    reservation_number = _field(details, r"予約番号") or _field(text, r"予約番号")
    if not reservation_number:
        raise ValueError("楽天トラベルの予約番号を確認できません。")

    check_in, arrival_time = _date_time(_field(details, r"チェックイン日時"))
    check_out, _ = _date_time(_field(details, r"チェックアウト日時"))
    nights = _number(_field(details, r"泊数"), r"(\d+)\s*泊")
    if not check_out and check_in and nights > 0:
        check_out = _add_days(check_in, nights)

    count_line = _field(details, r"人数")
    adults = _number(count_line, r"大人\s*(\d+)\s*[人名]")
    children = sum(
        int(value)
        for value in re.findall(r"(?:子供|小学生|幼児)[^\d\n]*(\d+)\s*[人名]", count_line or "")
    )

    guest_name = _field(details, r"会員氏名") or _field(details, r"宿泊者氏名")
    phone = _field(details, r"宿泊者連絡先") or _field(details, r"会員連絡先")
    room_name = _field(details, r"部屋タイプ")
    plan_name = _field(details, r"宿泊プラン")
    payment_method = _field(details, r"決済方法")
    total_price = _money(_field(details, r"合計\s*\(A\)"))
    room_count = _number(_field(details, r"部屋数"), r"(\d+)\s*室") or 1
    has_breakfast, has_dinner = _meal_flags(plan_name)

    return {
        "source": "Rakuten Travel",
        "eventType": event_type,
        "reservationNumber": reservation_number,
        "guestName": guest_name,
        "phone": phone,
        "email": None,
        "address": None,
        "checkIn": check_in,
        "checkOut": check_out,
        "arrivalTime": arrival_time,
        "nights": nights or None,
        "adults": adults or None,
        "children": children,
        "roomCount": room_count,
        "roomName": room_name,
        "planName": plan_name,
        "priceYen": total_price,
        "paymentMethod": payment_method,
        "hasBreakfast": has_breakfast,
        "hasDinner": has_dinner,
        "rawBody": text,
    }


def _jalan_room_counts(text: str) -> tuple[int, int]:
    room_lines = re.findall(r"(?m)^\s*\d+部屋目\s*[:：]\s*(.*?)$", text)
    target = "\n".join(room_lines) if room_lines else _field(text, r"1部屋目") or ""
    adults = sum(int(value) for value in re.findall(r"大人\s*[:：]?\s*(\d+)\s*名", target))
    children = sum(
        int(value)
        for value in re.findall(r"(?:子供|小学生|幼児)[^\d\n]*(\d+)\s*名", target)
    )
    return adults, children


def parse_jalan(subject: str, body: str) -> dict[str, Any]:
    text = normalize_text(body)
    event_type = _event_type(subject, "Jalan")
    reservation_number = _field(text, r"予約番号")
    if not reservation_number:
        raise ValueError("じゃらんの予約番号を確認できません。")

    check_in, arrival_time = _date_time(
        _field(text, r"宿泊日時") or _field(text, r"チェックイン日時")
    )
    nights = _number(_field(text, r"泊数"), r"(\d+)\s*泊")
    check_out = _add_days(check_in, nights) if check_in and nights > 0 else None
    adults, children = _jalan_room_counts(text)
    room_count = _number(_field(text, r"部屋数"), r"(\d+)\s*室") or 1
    guest_name = _field(text, r"宿泊代表者氏名")
    guest_name = re.sub(r"\s*様\s*$", "", guest_name or "").strip() or None
    address = _field(text, r"住所")
    phone = _field(text, r"宿泊代表者連絡先")
    email = _field(text, r"■?\s*予約者Eメールアドレス")
    room_name = _field(text, r"部屋タイプ")
    plan_name = _field(text, r"プラン")
    meal_text = _field(text, r"食事")
    has_breakfast, has_dinner = _meal_flags(plan_name, meal_text)
    payment_method = _field(text, r"決済情報")
    total_match = re.search(r"(?m)^\s*合計\s*[:：]\s*([\d,]+)\s*円", text)
    total_price = int(total_match.group(1).replace(",", "")) if total_match else None

    return {
        "source": "Jalan",
        "eventType": event_type,
        "reservationNumber": reservation_number,
        "guestName": guest_name,
        "phone": phone,
        "email": email,
        "address": address,
        "checkIn": check_in,
        "checkOut": check_out,
        "arrivalTime": arrival_time,
        "nights": nights or None,
        "adults": adults or None,
        "children": children,
        "roomCount": room_count,
        "roomName": room_name,
        "planName": plan_name,
        "priceYen": total_price,
        "paymentMethod": payment_method,
        "hasBreakfast": has_breakfast,
        "hasDinner": has_dinner,
        "rawBody": text,
    }


def parse_portal_email(subject: str, sender: str, body: str) -> dict[str, Any]:
    combined = normalize_text(f"{subject}\n{sender}")
    if "楽天トラベル" in combined or "mail.travel.rakuten.co.jp" in combined:
        return parse_rakuten(subject, body)
    if "じゃらん" in combined or "r.recruit.co.jp" in combined:
        return parse_jalan(subject, body)
    raise ValueError("楽天トラベル・じゃらんの通知ではありません。")


def _decode_data(data: str | None, charset: str | None = None) -> str:
    if not data:
        return ""
    padding = "=" * (-len(data) % 4)
    raw = base64.urlsafe_b64decode(data + padding)
    for encoding in (charset, "utf-8", "iso-2022-jp", "shift_jis", "cp932"):
        if not encoding:
            continue
        try:
            return raw.decode(encoding)
        except (LookupError, UnicodeDecodeError):
            continue
    return raw.decode("utf-8", errors="replace")


def _part_charset(part: dict[str, Any]) -> str | None:
    for header in part.get("headers", []) or []:
        if header.get("name", "").lower() != "content-type":
            continue
        match = re.search(
            r"charset=[\"']?([^;\"'\s]+)",
            header.get("value", ""),
            re.IGNORECASE,
        )
        if match:
            return match.group(1)
    return None


def _message_body(payload: dict[str, Any]) -> str:
    plain: list[str] = []
    html: list[str] = []

    def walk(part: dict[str, Any]) -> None:
        mime_type = part.get("mimeType", "")
        data = part.get("body", {}).get("data")
        if mime_type == "text/plain" and data:
            plain.append(_decode_data(data, _part_charset(part)))
        elif mime_type == "text/html" and data:
            html.append(_decode_data(data, _part_charset(part)))
        for child in part.get("parts", []) or []:
            walk(child)

    walk(payload)
    if plain:
        return "\n".join(plain)
    extractor = _HtmlTextExtractor()
    extractor.feed("\n".join(html))
    return extractor.text()


def _headers(payload: dict[str, Any]) -> dict[str, str]:
    return {
        item.get("name", "").lower(): item.get("value", "")
        for item in payload.get("headers", [])
    }


def _gmail_service():
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from googleapiclient.discovery import build

    credentials_path = ROOT / "credentials.json"
    token_path = ROOT / "token.json"
    if not credentials_path.exists():
        raise FileNotFoundError(f"credentials.json が見つかりません: {credentials_path}")

    credentials = None
    if token_path.exists():
        credentials = Credentials.from_authorized_user_file(str(token_path), SCOPES)
    if not credentials or not credentials.valid:
        if credentials and credentials.expired and credentials.refresh_token:
            credentials.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(str(credentials_path), SCOPES)
            credentials = flow.run_local_server(port=0)
        token_path.write_text(credentials.to_json(), encoding="utf-8")
    return build("gmail", "v1", credentials=credentials)


def fetch_messages() -> tuple[list[dict[str, Any]], list[str]]:
    service = _gmail_service()
    message_refs: list[dict[str, Any]] = []
    page_token = None
    while True:
        response = (
            service.users()
            .messages()
            .list(userId="me", q=QUERY, pageToken=page_token, maxResults=500)
            .execute()
        )
        message_refs.extend(response.get("messages", []))
        page_token = response.get("nextPageToken")
        if not page_token:
            break

    reservations: list[dict[str, Any]] = []
    errors: list[str] = []
    for ref in message_refs:
        message = (
            service.users().messages().get(userId="me", id=ref["id"], format="full").execute()
        )
        payload = message.get("payload", {})
        headers = _headers(payload)
        subject = headers.get("subject", "")
        sender = headers.get("from", "")
        body = _message_body(payload)
        try:
            parsed = parse_portal_email(subject, sender, body)
            parsed.update(
                {
                    "messageId": message.get("id"),
                    "threadId": message.get("threadId"),
                    "subject": subject,
                    "sender": sender,
                    "sentAt": _sent_at(message, headers),
                }
            )
            reservations.append(parsed)
        except Exception as error:  # Keep other messages importable.
            errors.append(f"{subject or ref['id']}: {error}")
    return reservations, errors


def _sent_at(message: dict[str, Any], headers: dict[str, str]) -> str | None:
    internal_date = message.get("internalDate")
    if internal_date:
        return datetime.fromtimestamp(int(internal_date) / 1000, timezone.utc).isoformat()
    try:
        return parsedate_to_datetime(headers.get("date", "")).isoformat()
    except (TypeError, ValueError):
        return None


def main() -> int:
    try:
        reservations, errors = fetch_messages()
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "generatedAt": datetime.now(timezone.utc).isoformat(),
                    "query": QUERY,
                    "count": len(reservations),
                    "reservations": reservations,
                    "errors": errors,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        print(f"楽天・じゃらん通知を {len(reservations)} 件取得しました。")
        if errors:
            print(f"解析できなかったメール: {len(errors)} 件")
        return 0
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
