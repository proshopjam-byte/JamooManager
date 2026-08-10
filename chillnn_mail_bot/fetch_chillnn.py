import base64
import json
import re
from datetime import datetime, timezone
from email import policy
from email.parser import BytesParser
from email.utils import parsedate_to_datetime
from html import unescape
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build


BASE_DIRECTORY = Path(__file__).resolve().parent
CREDENTIALS_PATH = BASE_DIRECTORY / "credentials.json"
TOKEN_PATH = BASE_DIRECTORY / "token.json"
OUTPUT_DIRECTORY = BASE_DIRECTORY / "output"
OUTPUT_PATH = OUTPUT_DIRECTORY / "chillnn_emails_latest.json"

SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
]

SEARCH_QUERY = (
    '{subject:"新規ご予約" subject:"ご予約内容の変更" subject:"ご予約内容のキャンセル"} '
    "after:2026/01/01"
)


def authenticate():
    credentials = None

    if TOKEN_PATH.exists():
        credentials = Credentials.from_authorized_user_file(
            TOKEN_PATH,
            SCOPES,
        )

    if credentials and credentials.expired and credentials.refresh_token:
        credentials.refresh(Request())

    if not credentials or not credentials.valid:
        if not CREDENTIALS_PATH.exists():
            raise FileNotFoundError(
                f"OAuth認証ファイルが見つかりません: "
                f"{CREDENTIALS_PATH}"
            )

        flow = InstalledAppFlow.from_client_secrets_file(
            CREDENTIALS_PATH,
            SCOPES,
        )

        credentials = flow.run_local_server(port=0)

    TOKEN_PATH.write_text(
        credentials.to_json(),
        encoding="utf-8",
    )

    return credentials


def html_to_text(value):
    value = re.sub(
        r"(?is)<(script|style).*?>.*?</\1>",
        "",
        value,
    )
    value = re.sub(
        r"(?i)<br\s*/?>",
        "\n",
        value,
    )
    value = re.sub(
        r"(?i)</(?:p|div|tr|li)>",
        "\n",
        value,
    )
    value = re.sub(
        r"(?s)<[^>]+>",
        "",
        value,
    )
    value = unescape(value)

    lines = [
        line.strip()
        for line in value.replace("\r\n", "\n").split("\n")
    ]

    return "\n".join(
        line for line in lines if line
    )


def content_text(part):
    try:
        content = part.get_content()
    except Exception:
        payload = part.get_payload(decode=True) or b""
        charset = part.get_content_charset() or "utf-8"
        return payload.decode(charset, errors="replace")

    if isinstance(content, bytes):
        charset = part.get_content_charset() or "utf-8"
        return content.decode(charset, errors="replace")

    return str(content)


def extract_body(message):
    plain_parts = []
    html_parts = []

    parts = (
        message.walk()
        if message.is_multipart()
        else [message]
    )

    for part in parts:
        if part.is_multipart():
            continue

        if part.get_content_disposition() == "attachment":
            continue

        content_type = part.get_content_type()
        text = content_text(part)

        if content_type == "text/plain":
            plain_parts.append(text)
        elif content_type == "text/html":
            html_parts.append(text)

    if plain_parts:
        return "\n".join(plain_parts).strip()

    if html_parts:
        return html_to_text("\n".join(html_parts)).strip()

    return ""


def message_datetime(message, internal_date):
    date_header = message.get("Date")

    if date_header:
        try:
            value = parsedate_to_datetime(str(date_header))

            if value.tzinfo is None:
                value = value.replace(tzinfo=timezone.utc)

            return value.astimezone()
        except (TypeError, ValueError):
            pass

    timestamp = int(internal_date) / 1000
    return datetime.fromtimestamp(
        timestamp,
        tz=timezone.utc,
    ).astimezone()


def list_message_ids(service):
    message_ids = []
    page_token = None

    while True:
        result = service.users().messages().list(
            userId="me",
            q=SEARCH_QUERY,
            maxResults=100,
            pageToken=page_token,
        ).execute()

        message_ids.extend(
            item["id"]
            for item in result.get("messages", [])
        )

        page_token = result.get("nextPageToken")

        if not page_token:
            break

    return message_ids


def load_message(service, message_id):
    result = service.users().messages().get(
        userId="me",
        id=message_id,
        format="raw",
    ).execute()

    raw_value = result["raw"]
    padding = "=" * (-len(raw_value) % 4)
    raw_bytes = base64.urlsafe_b64decode(
        raw_value + padding
    )

    message = BytesParser(
        policy=policy.default,
    ).parsebytes(raw_bytes)

    sent_at = message_datetime(
        message,
        result.get("internalDate", "0"),
    )

    return {
        "messageId": result["id"],
        "rfcMessageId": str(
            message.get("Message-ID", "")
        ).strip(),
        "subject": str(
            message.get("Subject", "")
        ).strip(),
        "sentAt": sent_at.isoformat(
            timespec="seconds"
        ),
        "body": extract_body(message),
        "_sort": sent_at.timestamp(),
    }


def main():
    credentials = authenticate()

    service = build(
        "gmail",
        "v1",
        credentials=credentials,
    )

    message_ids = list_message_ids(service)
    messages = []

    for index, message_id in enumerate(
        message_ids,
        start=1,
    ):
        print(
            f"CHILLNNメールを取得中: "
            f"{index}/{len(message_ids)}"
        )
        messages.append(
            load_message(service, message_id)
        )

    messages.sort(key=lambda item: item["_sort"])

    for message in messages:
        message.pop("_sort", None)

    output = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(
            timezone.utc
        ).astimezone().isoformat(
            timespec="seconds"
        ),
        "count": len(messages),
        "messages": messages,
    }

    OUTPUT_DIRECTORY.mkdir(
        parents=True,
        exist_ok=True,
    )

    OUTPUT_PATH.write_text(
        json.dumps(
            output,
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    print("")
    print(
        f"CHILLNNメールを{len(messages)}件取得しました。"
    )
    print(f"保存先: {OUTPUT_PATH}")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"CHILLNNメール取得エラー: {error}")
        raise SystemExit(1)