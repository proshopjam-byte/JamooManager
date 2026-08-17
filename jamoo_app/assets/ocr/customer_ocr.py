import argparse
import base64
import json
import os
import re
import shutil
import subprocess
import urllib.error
import urllib.request
from pathlib import Path


WINDOWS_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
VISION_API_URL = "https://vision.googleapis.com/v1/images:annotate"
FIELD_BOUNDS = {
    "fullName": (0.185, 0.012, 0.820, 0.145),
    "address": (0.185, 0.145, 0.820, 0.275),
    "phone": (0.650, 0.145, 0.995, 0.275),
    "country": (0.185, 0.585, 0.560, 0.770),
    "email": (0.185, 0.700, 0.850, 0.900),
}
COUNTRY_ALIASES = (
    (r"(?:日本|\bJapanese\b|\bJapan\b)", "Japan"),
    (r"(?:\bAustralian\b|\bAustralia\b)", "Australia"),
    (r"(?:\bFrench\b|\bFrance\b)", "France"),
    (r"(?:\bGerman\b|\bGermany\b)", "Germany"),
    (r"(?:\bBritish\b|\bUnited Kingdom\b|\bUK\b)", "United Kingdom"),
    (r"(?:\bAmerican\b|\bUnited States\b|\bUSA\b)", "United States"),
    (r"(?:\bCanadian\b|\bCanada\b)", "Canada"),
    (r"(?:\bChinese\b|\bChina\b)", "China"),
    (r"(?:\bKorean\b|\bSouth Korea\b|\bKorea\b)", "South Korea"),
    (r"(?:\bTaiwanese\b|\bTaiwan\b)", "Taiwan"),
    (r"(?:\bItalian\b|\bItaly\b)", "Italy"),
    (r"(?:\bSpanish\b|\bSpain\b)", "Spain"),
    (r"(?:\bDutch\b|\bNetherlands\b)", "Netherlands"),
    (r"(?:\bSwiss\b|\bSwitzerland\b)", "Switzerland"),
    (r"(?:\bAustrian\b|\bAustria\b)", "Austria"),
    (r"(?:\bIndian\b|\bIndia\b)", "India"),
    (r"(?:\bThai\b|\bThailand\b)", "Thailand"),
    (r"(?:\bVietnamese\b|\bVietnam\b)", "Vietnam"),
    (r"(?:\bIndonesian\b|\bIndonesia\b)", "Indonesia"),
    (r"(?:\bMalaysian\b|\bMalaysia\b)", "Malaysia"),
    (r"(?:\bSingaporean\b|\bSingapore\b)", "Singapore"),
    (r"(?:\bFilipino\b|\bPhilippines\b)", "Philippines"),
    (r"(?:\bNew Zealand(?:er)?\b)", "New Zealand"),
    (r"(?:\bBrazilian\b|\bBrazil\b)", "Brazil"),
    (r"(?:\bMexican\b|\bMexico\b)", "Mexico"),
)


def emit(payload, exit_code=0):
    print(json.dumps(payload, ensure_ascii=True))
    raise SystemExit(exit_code)


def find_tesseract():
    found = shutil.which("tesseract")
    if found:
        return found
    candidates = [
        Path(os.environ.get("ProgramFiles", r"C:\Program Files"))
        / "Tesseract-OCR"
        / "tesseract.exe",
        Path(os.environ.get("LOCALAPPDATA", ""))
        / "Programs"
        / "Tesseract-OCR"
        / "tesseract.exe",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)
    return None


def load_image_dependencies():
    try:
        import cv2
        import numpy as np
    except ImportError as error:
        raise RuntimeError(
            "Image correction requires OpenCV. Run: "
            "py -m pip install opencv-python-headless"
        ) from error
    return cv2, np


def available_languages(tesseract):
    result = subprocess.run(
        [tesseract, "--list-langs"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=WINDOWS_NO_WINDOW,
    )
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def load_cloud_api_key():
    value = os.environ.get("GOOGLE_CLOUD_VISION_API_KEY", "").strip()
    if value:
        return value
    key_file = Path(__file__).with_name("vision_api_key.txt")
    if key_file.is_file():
        value = key_file.read_text(encoding="utf-8").strip()
    if not value:
        raise RuntimeError(
            "Google Cloud Vision API key is not configured in JamooManager."
        )
    return value


def read_image(path, cv2, np):
    data = np.fromfile(str(path), dtype=np.uint8)
    image = cv2.imdecode(data, cv2.IMREAD_COLOR)
    if image is None:
        raise RuntimeError("The selected image could not be opened.")
    return image


def order_points(points, np):
    points = points.reshape(4, 2).astype("float32")
    ordered = np.zeros((4, 2), dtype="float32")
    sums = points.sum(axis=1)
    differences = np.diff(points, axis=1).reshape(-1)
    ordered[0] = points[np.argmin(sums)]
    ordered[2] = points[np.argmax(sums)]
    ordered[1] = points[np.argmin(differences)]
    ordered[3] = points[np.argmax(differences)]
    return ordered


def rectify_form(image, cv2, np):
    original = image
    height, width = original.shape[:2]
    scale = min(1.0, 1800.0 / max(height, width))
    working = cv2.resize(
        original,
        (max(1, int(width * scale)), max(1, int(height * scale))),
        interpolation=cv2.INTER_AREA,
    )
    gray = cv2.cvtColor(working, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blurred, 45, 140)
    edges = cv2.dilate(edges, np.ones((3, 3), np.uint8), iterations=1)
    contours, _ = cv2.findContours(
        edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE
    )
    image_area = working.shape[0] * working.shape[1]
    candidates = []
    for contour in sorted(contours, key=cv2.contourArea, reverse=True)[:40]:
        area = cv2.contourArea(contour)
        if area < image_area * 0.16:
            continue
        perimeter = cv2.arcLength(contour, True)
        polygon = cv2.approxPolyDP(contour, 0.02 * perimeter, True)
        if len(polygon) != 4 or not cv2.isContourConvex(polygon):
            continue
        points = order_points(polygon, np)
        top = np.linalg.norm(points[1] - points[0])
        bottom = np.linalg.norm(points[2] - points[3])
        left = np.linalg.norm(points[3] - points[0])
        right = np.linalg.norm(points[2] - points[1])
        short_side = min(max(top, bottom), max(left, right))
        long_side = max(max(top, bottom), max(left, right))
        if short_side <= 0 or long_side / short_side > 2.25:
            continue
        candidates.append((area, points))

    if not candidates:
        return original, False

    _, points = max(candidates, key=lambda item: item[0])
    points /= scale
    top_left, top_right, bottom_right, bottom_left = points
    target_width = int(
        max(
            np.linalg.norm(top_right - top_left),
            np.linalg.norm(bottom_right - bottom_left),
        )
    )
    target_height = int(
        max(
            np.linalg.norm(bottom_left - top_left),
            np.linalg.norm(bottom_right - top_right),
        )
    )
    if target_width < 100 or target_height < 100:
        return original, False

    output_width = 1800
    output_height = max(700, int(output_width * target_height / target_width))
    destination = np.array(
        [
            [0, 0],
            [output_width - 1, 0],
            [output_width - 1, output_height - 1],
            [0, output_height - 1],
        ],
        dtype="float32",
    )
    transform = cv2.getPerspectiveTransform(points, destination)
    corrected = cv2.warpPerspective(
        original,
        transform,
        (output_width, output_height),
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=(255, 255, 255),
    )
    return corrected, True


def detect_rotation(tesseract, image, cv2):
    encoded_ok, encoded = cv2.imencode(".png", image)
    if not encoded_ok:
        return 0
    result = subprocess.run(
        [tesseract, "stdin", "stdout", "--psm", "0"],
        input=encoded.tobytes(),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        creationflags=WINDOWS_NO_WINDOW,
    )
    output = result.stdout.decode("utf-8", errors="replace")
    match = re.search(r"Rotate:\s*(0|90|180|270)", output)
    if match:
        return int(match.group(1))
    height, width = image.shape[:2]
    return 90 if height > width * 1.08 else 0


def rotate_image(image, degrees, cv2):
    if degrees == 90:
        return cv2.rotate(image, cv2.ROTATE_90_CLOCKWISE)
    if degrees == 180:
        return cv2.rotate(image, cv2.ROTATE_180)
    if degrees == 270:
        return cv2.rotate(image, cv2.ROTATE_90_COUNTERCLOCKWISE)
    return image


def remove_form_lines(gray, cv2, np):
    binary = cv2.threshold(
        gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU
    )[1]
    height, width = binary.shape[:2]
    horizontal_kernel = cv2.getStructuringElement(
        cv2.MORPH_RECT, (max(24, width // 18), 1)
    )
    vertical_kernel = cv2.getStructuringElement(
        cv2.MORPH_RECT, (1, max(24, height // 8))
    )
    horizontal = cv2.morphologyEx(binary, cv2.MORPH_OPEN, horizontal_kernel)
    vertical = cv2.morphologyEx(binary, cv2.MORPH_OPEN, vertical_kernel)
    lines = cv2.bitwise_or(horizontal, vertical)
    cleaned = cv2.bitwise_and(binary, cv2.bitwise_not(lines))
    cleaned = cv2.morphologyEx(
        cleaned,
        cv2.MORPH_CLOSE,
        np.ones((2, 2), np.uint8),
        iterations=1,
    )
    return cv2.bitwise_not(cleaned)


def prepare_image(image, cv2, np, thresholded=False):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    gray = cv2.createCLAHE(clipLimit=2.2, tileGridSize=(8, 8)).apply(gray)
    cleaned = remove_form_lines(gray, cv2, np)
    if thresholded:
        cleaned = cv2.adaptiveThreshold(
            cleaned,
            255,
            cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv2.THRESH_BINARY,
            41,
            13,
        )
    return cv2.copyMakeBorder(
        cleaned, 18, 18, 18, 18, cv2.BORDER_CONSTANT, value=255
    )


def crop_relative(image, bounds):
    height, width = image.shape[:2]
    left, top, right, bottom = bounds
    x1 = max(0, min(width - 1, int(left * width)))
    y1 = max(0, min(height - 1, int(top * height)))
    x2 = max(x1 + 1, min(width, int(right * width)))
    y2 = max(y1 + 1, min(height, int(bottom * height)))
    return image[y1:y2, x1:x2]


def run_tesseract(
    tesseract,
    image,
    language,
    cv2,
    psm=6,
    output_format="text",
    whitelist=None,
):
    encoded_ok, encoded = cv2.imencode(".png", image)
    if not encoded_ok:
        raise RuntimeError("The OCR image could not be prepared.")
    arguments = [
        tesseract,
        "stdin",
        "stdout",
        "-l",
        language,
        "--oem",
        "1",
        "--psm",
        str(psm),
    ]
    if whitelist:
        arguments.extend(["-c", f"tessedit_char_whitelist={whitelist}"])
    if output_format == "tsv":
        arguments.append("tsv")
    result = subprocess.run(
        arguments,
        input=encoded.tobytes(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        creationflags=WINDOWS_NO_WINDOW,
    )
    stdout = result.stdout.decode("utf-8", errors="replace")
    stderr = result.stderr.decode("utf-8", errors="replace")
    if result.returncode != 0:
        raise RuntimeError(stderr.strip() or "Tesseract OCR failed.")
    return stdout.strip()


def tsv_text_and_confidence(tsv):
    words = []
    confidences = []
    lines = tsv.splitlines()
    if not lines:
        return "", -1.0
    headers = lines[0].split("\t")
    try:
        text_index = headers.index("text")
        confidence_index = headers.index("conf")
    except ValueError:
        return "", -1.0
    for line in lines[1:]:
        columns = line.split("\t")
        if len(columns) <= max(text_index, confidence_index):
            continue
        word = columns[text_index].strip()
        if not word:
            continue
        try:
            confidence = float(columns[confidence_index])
        except ValueError:
            confidence = -1.0
        words.append(word)
        if confidence >= 0:
            confidences.append(confidence)
    average = sum(confidences) / len(confidences) if confidences else -1.0
    return " ".join(words).strip(), average


def best_field_reading(
    tesseract, image, language, cv2, np, whitelist=None
):
    candidates = []
    for thresholded in (False, True):
        prepared = prepare_image(image, cv2, np, thresholded=thresholded)
        for psm in (7, 6, 13):
            tsv = run_tesseract(
                tesseract,
                prepared,
                language,
                cv2,
                psm=psm,
                output_format="tsv",
                whitelist=whitelist,
            )
            text, confidence = tsv_text_and_confidence(tsv)
            if text:
                candidates.append((confidence, len(text), text))
    if not candidates:
        return None, -1.0
    confidence, _, text = max(candidates, key=lambda item: (item[0], item[1]))
    return clean_value(text), confidence


def clean_value(value):
    if value is None:
        return None
    value = re.sub(r"\s+", " ", value).strip(" :：\t|_")
    return value or None


def extract_email(value):
    if not value:
        return None
    normalized = value.replace("＠", "@").replace("．", ".")
    normalized = re.sub(r"\s*@\s*", "@", normalized)
    normalized = re.sub(r"\s*\.\s*", ".", normalized)
    match = re.search(
        r"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\."
        r"(?:co\.jp|ne\.jp|or\.jp|com|net|org|info|biz|jp|au|uk|fr|de|"
        r"it|es|nl|ch|at|in|th|vn|id|my|sg|ph|nz|br|mx)",
        normalized,
        re.I,
    )
    if not match:
        return None
    candidate = match.group(0)
    local_part, domain_part = candidate.split("@", 1)
    lowered = local_part.lower()
    for marker in ("passportnumber", "emailaddress", "nationality"):
        marker_index = lowered.rfind(marker)
        if marker_index >= 0:
            local_part = local_part[marker_index + len(marker) :]
            lowered = local_part.lower()
    if not local_part:
        return None
    return clean_value(f"{local_part}@{domain_part}")


def extract_country(value, allow_free_text=False):
    if not value:
        return None
    for pattern, country in COUNTRY_ALIASES:
        if re.search(pattern, value, re.I):
            return country
    if not allow_free_text:
        return None
    cleaned = re.sub(
        r"(?:国籍|外国人の場合|nationality|passport\s*number)",
        " ",
        value,
        flags=re.I,
    )
    cleaned = re.sub(r"[\d|_:：]+", " ", cleaned)
    cleaned = clean_value(cleaned)
    if cleaned and 2 <= len(cleaned) <= 40:
        return cleaned
    return None


def extract_phone(value):
    if not value:
        return None
    normalized = value.translate(str.maketrans({"O": "0", "o": "0"}))
    international = re.search(
        r"\+\s*\d(?:[\s().\-]*\d){7,14}", normalized
    )
    if international:
        digits = re.sub(r"\D", "", international.group(0))
        if 8 <= len(digits) <= 15:
            return "+" + digits

    digits = re.sub(r"\D", "", normalized)
    japanese_mobile = re.search(r"0(?:50|70|80|90)\d{8}", digits)
    if japanese_mobile:
        return japanese_mobile.group(0)
    if digits.startswith("81") and len(digits) >= 11:
        digits = "0" + digits[2:]
    if 8 <= len(digits) <= 15:
        return digits
    return None


def extract_postal(value):
    if not value:
        return None
    match = re.search(r"(?:〒\s*)?(\d{3})[\s\-ー−]*(\d{4})", value)
    if match:
        return f"{match.group(1)}-{match.group(2)}"

    first_half = re.search(r"(?<!\d)(\d{3})(?!\d)", value)
    second_half = re.search(r"[\-ー−]\s*(\d{4})(?!\d)", value)
    if first_half and second_half:
        return f"{first_half.group(1)}-{second_half.group(1)}"

    international = re.search(r"(?<!\d)(\d{4,6})(?!\d)", value)
    return international.group(1) if international else None


def clean_address(value):
    if not value:
        return None
    address = value
    postal = extract_postal(address)

    address = re.sub(
        r"\+\s*\d(?:[\s().\-]*\d){7,14}", " ", address
    )
    address = re.sub(
        r"0(?:50|70|80|90)(?:[\s()\-]*\d){8}", " ", address
    )
    address = re.sub(
        r"\bTEL\b\s*[:：]?\s*(?:\+?\d[\d\s().\-]{6,}\d)",
        " ",
        address,
        flags=re.I,
    )
    address = re.sub(r"\bTEL\b", " ", address, flags=re.I)
    address = re.sub(r"(?:住所|address)", " ", address, flags=re.I)

    if postal:
        if re.fullmatch(r"\d{3}-\d{4}", postal):
            first, second = postal.split("-", 1)
            address = re.sub(
                rf"(?<!\d){re.escape(first)}(?!\d)", " ", address, count=1
            )
            address = re.sub(
                rf"[\-ー−]\s*{re.escape(second)}(?!\d)",
                " ",
                address,
                count=1,
            )
        else:
            address = re.sub(
                rf"(?<!\d){re.escape(postal)}(?!\d)",
                " ",
                address,
                count=1,
            )

    address = re.sub(
        r"(?<=[\u3040-\u30ff\u3400-\u9fff])\s+"
        r"(?=[\u3040-\u30ff\u3400-\u9fff])",
        "",
        address,
    )
    return clean_value(address)


def general_suggestions(text):
    return {
        "fullName": None,
        "email": extract_email(text),
        "phone": extract_phone(text),
        "postalCode": extract_postal(text),
        "address": None,
        "country": extract_country(text),
    }


def run_cloud_vision(api_key, image, cv2):
    encoded_ok, encoded = cv2.imencode(
        ".jpg", image, [int(cv2.IMWRITE_JPEG_QUALITY), 94]
    )
    if not encoded_ok:
        raise RuntimeError("The cloud OCR image could not be prepared.")
    request_body = {
        "requests": [
            {
                "image": {
                    "content": base64.b64encode(encoded.tobytes()).decode(
                        "ascii"
                    )
                },
                "features": [{"type": "DOCUMENT_TEXT_DETECTION"}],
            }
        ]
    }
    request = urllib.request.Request(
        VISION_API_URL,
        data=json.dumps(request_body).encode("utf-8"),
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "X-Goog-Api-Key": api_key,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        try:
            decoded = json.loads(detail)
            message = decoded.get("error", {}).get("message")
        except json.JSONDecodeError:
            message = None
        raise RuntimeError(
            message or f"Google Cloud Vision returned HTTP {error.code}."
        ) from error
    except urllib.error.URLError as error:
        raise RuntimeError(
            "Google Cloud Vision could not be reached. Check the internet connection."
        ) from error

    responses = payload.get("responses") or []
    if not responses:
        raise RuntimeError("Google Cloud Vision returned no OCR response.")
    result = responses[0]
    if result.get("error"):
        raise RuntimeError(
            result["error"].get("message")
            or "Google Cloud Vision OCR failed."
        )
    annotation = result.get("fullTextAnnotation") or {}
    text = (annotation.get("text") or "").strip()
    words = cloud_words(annotation)
    return text, words


def cloud_words(annotation):
    words = []
    for page in annotation.get("pages") or []:
        page_width = max(1, int(page.get("width") or 1))
        page_height = max(1, int(page.get("height") or 1))
        for block in page.get("blocks") or []:
            for paragraph in block.get("paragraphs") or []:
                for word in paragraph.get("words") or []:
                    text = "".join(
                        symbol.get("text", "")
                        for symbol in word.get("symbols") or []
                    ).strip()
                    if not text:
                        continue
                    vertices = (
                        word.get("boundingBox", {}).get("vertices") or []
                    )
                    xs = [int(vertex.get("x") or 0) for vertex in vertices]
                    ys = [int(vertex.get("y") or 0) for vertex in vertices]
                    if not xs or not ys:
                        continue
                    confidence_value = word.get("confidence")
                    confidence = (
                        float(confidence_value)
                        if confidence_value is not None
                        else 1.0
                    )
                    words.append(
                        {
                            "text": text,
                            "x": ((min(xs) + max(xs)) / 2) / page_width,
                            "y": ((min(ys) + max(ys)) / 2) / page_height,
                            "left": min(xs) / page_width,
                            "right": max(xs) / page_width,
                            "top": min(ys) / page_height,
                            "bottom": max(ys) / page_height,
                            "height": max(1, max(ys) - min(ys)) / page_height,
                            "confidence": confidence,
                        }
                    )
    return words


def cloud_field_text(words, bounds):
    left, top, right, bottom = bounds
    selected = [
        word
        for word in words
        if left <= word["x"] <= right
        and top <= word["y"] <= bottom
        and word["confidence"] >= 0.10
    ]
    selected.sort(key=lambda word: (word["y"], word["x"]))
    lines = []
    for word in selected:
        best_line = None
        best_distance = None
        for line in lines:
            distance = abs(word["y"] - line["y"])
            tolerance = max(
                0.018,
                min(0.035, (word["height"] + line["height"]) * 0.65),
            )
            if distance <= tolerance and (
                best_distance is None or distance < best_distance
            ):
                best_line = line
                best_distance = distance
        if best_line is None:
            lines.append(
                {
                    "words": [word],
                    "y": word["y"],
                    "height": word["height"],
                }
            )
            continue
        best_line["words"].append(word)
        count = len(best_line["words"])
        best_line["y"] = (
            best_line["y"] * (count - 1) + word["y"]
        ) / count
        best_line["height"] = max(best_line["height"], word["height"])

    lines.sort(key=lambda line: line["y"])
    line_texts = []
    for line in lines:
        line["words"].sort(key=lambda word: word["x"])
        line_texts.append(" ".join(word["text"] for word in line["words"]))
    return clean_value(" ".join(line_texts))


def cloud_suggestions(text, words, form_detected):
    values = general_suggestions(text)
    if not form_detected:
        return values
    full_name = cloud_field_text(words, FIELD_BOUNDS["fullName"])
    address = cloud_field_text(words, FIELD_BOUNDS["address"])
    phone_text = cloud_field_text(words, FIELD_BOUNDS["phone"])
    country_text = cloud_field_text(words, FIELD_BOUNDS["country"])
    email_text = cloud_field_text(words, FIELD_BOUNDS["email"])
    if full_name:
        values["fullName"] = full_name
    if address:
        values["address"] = clean_address(address)
        values["postalCode"] = extract_postal(address)
    field_phone = extract_phone(phone_text)
    if field_phone:
        values["phone"] = field_phone
    field_email = extract_email(email_text)
    if field_email:
        values["email"] = field_email
    field_country = extract_country(country_text, allow_free_text=True)
    if field_country:
        values["country"] = field_country
    return values


def process_page(
    image, tesseract, language, cv2, np, engine="local", api_key=None
):
    corrected, form_detected = rectify_form(image, cv2, np)
    rotation = detect_rotation(tesseract, corrected, cv2)
    corrected = rotate_image(corrected, rotation, cv2)

    if engine == "cloud":
        full_text, words = run_cloud_vision(api_key, corrected, cv2)
        values = cloud_suggestions(full_text, words, form_detected)
        return full_text, values, form_detected

    full_prepared = prepare_image(corrected, cv2, np, thresholded=False)
    full_text = run_tesseract(
        tesseract, full_prepared, language, cv2, psm=6
    )
    values = general_suggestions(full_text)
    if not form_detected:
        return full_text, values, False

    fields = {
        "fullName": {
            "bounds": FIELD_BOUNDS["fullName"],
            "language": language,
        },
        "address": {
            "bounds": FIELD_BOUNDS["address"],
            "language": language,
        },
        "phone": {
            "bounds": FIELD_BOUNDS["phone"],
            "language": "eng",
            "whitelist": "0123456789-+() ",
        },
        "country": {
            "bounds": FIELD_BOUNDS["country"],
            "language": language,
        },
        "email": {
            "bounds": FIELD_BOUNDS["email"],
            "language": "eng",
            "whitelist": (
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
                "0123456789._%+-@"
            ),
        },
    }
    readings = {}
    confidences = {}
    for field_name, settings in fields.items():
        cropped = crop_relative(corrected, settings["bounds"])
        text, confidence = best_field_reading(
            tesseract,
            cropped,
            settings["language"],
            cv2,
            np,
            whitelist=settings.get("whitelist"),
        )
        readings[field_name] = text
        confidences[field_name] = confidence

    if readings["fullName"] and confidences["fullName"] >= 18:
        values["fullName"] = readings["fullName"]
    if readings["address"] and confidences["address"] >= 18:
        values["address"] = readings["address"]
        values["postalCode"] = extract_postal(readings["address"])
    field_phone = extract_phone(readings["phone"])
    if field_phone:
        values["phone"] = field_phone
    field_email = extract_email(readings["email"])
    if field_email:
        values["email"] = field_email
    field_country = extract_country(
        readings["country"], allow_free_text=True
    )
    if field_country:
        values["country"] = field_country
    return full_text, values, True


def pdf_images(input_path, cv2, np):
    try:
        import pymupdf
    except ImportError as error:
        raise RuntimeError(
            "PDF OCR requires PyMuPDF. Run: py -m pip install pymupdf"
        ) from error
    images = []
    with pymupdf.open(input_path) as document:
        for page in document:
            pixmap = page.get_pixmap(
                matrix=pymupdf.Matrix(3.0, 3.0), alpha=False
            )
            data = np.frombuffer(pixmap.tobytes("png"), dtype=np.uint8)
            image = cv2.imdecode(data, cv2.IMREAD_COLOR)
            if image is not None:
                images.append(image)
    if not images:
        raise RuntimeError("The PDF did not contain a readable page.")
    return images


def export_page_attachments(input_path, images, output_directory, cv2):
    if not output_directory:
        return [None for _ in images]

    output_path = Path(output_directory)
    output_path.mkdir(parents=True, exist_ok=True)
    if input_path.suffix.lower() != ".pdf":
        return [
            {
                "attachmentPath": str(input_path.resolve()),
                "attachmentFileName": input_path.name,
                "attachmentMimeType": mime_type_for(input_path.suffix),
            }
        ]

    safe_stem = re.sub(r"[^A-Za-z0-9._-]+", "_", input_path.stem).strip("_")
    if not safe_stem:
        safe_stem = "checkin_card"
    attachments = []
    for page_index, image in enumerate(images):
        file_name = f"{safe_stem}_page_{page_index + 1}.png"
        page_path = output_path / file_name
        encoded_ok, encoded = cv2.imencode(".png", image)
        if not encoded_ok:
            raise RuntimeError(
                f"Page {page_index + 1} could not be prepared for attachment."
            )
        page_path.write_bytes(encoded.tobytes())
        attachments.append(
            {
                "attachmentPath": str(page_path.resolve()),
                "attachmentFileName": file_name,
                "attachmentMimeType": "image/png",
            }
        )
    return attachments


def mime_type_for(extension):
    value = extension.lower().lstrip(".")
    if value == "pdf":
        return "application/pdf"
    if value == "png":
        return "image/png"
    if value == "bmp":
        return "image/bmp"
    if value in ("tif", "tiff"):
        return "image/tiff"
    return "image/jpeg"


def combine_suggestions(page_values):
    combined = {
        "fullName": None,
        "email": None,
        "phone": None,
        "postalCode": None,
        "address": None,
        "country": None,
    }
    for values in page_values:
        for key in combined:
            if combined[key] is None and values.get(key):
                combined[key] = values[key]
    return combined


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument(
        "--engine", choices=("local", "cloud"), default="local"
    )
    parser.add_argument("--page-output-dir")
    args = parser.parse_args()
    input_path = Path(args.input)
    if not input_path.is_file():
        emit({"ok": False, "error": "The selected file was not found."}, 2)

    tesseract = find_tesseract()
    if not tesseract:
        emit(
            {
                "ok": False,
                "error": (
                    "Tesseract OCR is not installed. Install it first, "
                    "then restart JamooManager."
                ),
            },
            3,
        )

    try:
        cv2, np = load_image_dependencies()
        languages = available_languages(tesseract)
        has_japanese = "jpn" in languages
        language = "jpn+eng" if has_japanese else "eng"
        api_key = load_cloud_api_key() if args.engine == "cloud" else None
        if input_path.suffix.lower() == ".pdf":
            images = pdf_images(input_path, cv2, np)
        else:
            images = [read_image(input_path, cv2, np)]
        page_attachments = export_page_attachments(
            input_path, images, args.page_output_dir, cv2
        )

        page_texts = []
        page_values = []
        page_results = []
        detected_pages = 0
        for page_index, image in enumerate(images):
            text, values, form_detected = process_page(
                image,
                tesseract,
                language,
                cv2,
                np,
                engine=args.engine,
                api_key=api_key,
            )
            page_texts.append(text)
            page_values.append(values)
            page_result = {
                "pageNumber": page_index + 1,
                "text": text,
                "suggestions": values,
                "formDetected": form_detected,
            }
            attachment = page_attachments[page_index]
            if attachment:
                page_result.update(attachment)
            page_results.append(page_result)
            if form_detected:
                detected_pages += 1
    except Exception as error:
        emit({"ok": False, "error": str(error)}, 4)

    warnings = []
    if args.engine == "local" and not has_japanese:
        warnings.append(
            "Japanese OCR data (jpn.traineddata) is not installed. "
            "Japanese handwriting and addresses may not be recognized."
        )
    if detected_pages == 0:
        warnings.append(
            "The check-in form border was not detected. "
            "Try a brighter, sharper image showing the entire form."
        )
    emit(
        {
            "ok": True,
            "text": "\n\n--- page ---\n\n".join(page_texts),
            "suggestions": combine_suggestions(page_values),
            "pages": page_results,
            "engine": args.engine,
            "warning": "\n".join(warnings) or None,
            "formDetected": detected_pages > 0,
        }
    )


if __name__ == "__main__":
    main()
