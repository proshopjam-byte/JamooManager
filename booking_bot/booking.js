'use strict';

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const readline = require('readline/promises');
const { stdin: input, stdout: output } = require('process');

const BOOKING_URL = 'https://admin.booking.com';
const PROFILE_DIR = path.join(__dirname, 'booking-profile');
const OUTPUT_DIR = path.join(__dirname, 'output');
const LATEST_JSON_PATH = path.join(OUTPUT_DIR, 'reservations_latest.json');

const ENGLISH_MONTHS = {
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
  jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
};

function normalizeText(value) {
  return String(value ?? '')
    .replace(/\r/g, '')
    .replace(/[\u00a0\u3000]/g, ' ')
    .replace(/[ \t]+/g, ' ')
    .trim();
}

function splitLines(bodyText) {
  return String(bodyText ?? '')
    .replace(/\r/g, '')
    .split('\n')
    .map(normalizeText)
    .filter(Boolean);
}

function toIsoDate(value) {
  const text = normalizeText(value);

  const japaneseMatch = text.match(
    /(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日/
  );

  if (japaneseMatch) {
    const [, year, month, day] = japaneseMatch;
    return [
      year,
      String(month).padStart(2, '0'),
      String(day).padStart(2, '0'),
    ].join('-');
  }

  const englishMatch = text.match(
    /\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2}),\s*(\d{4})\b/i
  );

  if (englishMatch) {
    const [, monthName, day, year] = englishMatch;
    const month = ENGLISH_MONTHS[monthName.toLowerCase()];

    return [
      year,
      String(month).padStart(2, '0'),
      String(day).padStart(2, '0'),
    ].join('-');
  }

  return null;
}

function parseDateRange(value) {
  const text = normalizeText(value);
  const separators = '[–—－〜～~-]';

  const japanesePattern = new RegExp(
    `(\\d{4}年\\s*\\d{1,2}月\\s*\\d{1,2}日)\\s*${separators}\\s*` +
      `(\\d{4}年\\s*\\d{1,2}月\\s*\\d{1,2}日)`
  );

  const englishDate =
    '(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\s+\\d{1,2},\\s*\\d{4}';

  const englishPattern = new RegExp(
    `(${englishDate})\\s*${separators}\\s*(${englishDate})`,
    'i'
  );

  const match = text.match(japanesePattern) ?? text.match(englishPattern);
  if (!match) return null;

  const checkIn = toIsoDate(match[1]);
  const checkOut = toIsoDate(match[2]);

  if (!checkIn || !checkOut) return null;
  return { checkIn, checkOut };
}

function toNumber(value) {
  if (value === null || value === undefined) return null;

  const cleaned = String(value).replace(/[^\d-]/g, '');
  if (!cleaned || cleaned === '-') return null;

  const number = Number(cleaned);
  return Number.isFinite(number) ? number : null;
}

function createTimestamp(date = new Date()) {
  const parts = new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'Asia/Tokyo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  })
    .formatToParts(date)
    .reduce((result, part) => {
      result[part.type] = part.value;
      return result;
    }, {});

  return `${parts.year}-${parts.month}-${parts.day}_${parts.hour}-${parts.minute}-${parts.second}`;
}

function createGeneratedAt(date = new Date()) {
  const formatter = new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'Asia/Tokyo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  });

  return `${formatter.format(date).replace(' ', 'T')}+09:00`;
}

function parseStayInfo(lines) {
  const joined = lines.join(' ');

  const nightsMatch =
    joined.match(/(\d+)\s*(?:night|nights)\b/i) ??
    joined.match(/(\d+)\s*泊/);

  const adultsMatch =
    joined.match(/(\d+)\s*(?:adult|adults)\b/i) ??
    joined.match(/大人\s*(\d+)\s*名/);

  const childrenMatch =
    joined.match(/(\d+)\s*(?:child|children)\b/i) ??
    joined.match(/子供\s*(\d+)\s*名/);

  return {
    nights: nightsMatch ? toNumber(nightsMatch[1]) : null,
    adults: adultsMatch ? toNumber(adultsMatch[1]) : null,
    children: childrenMatch ? toNumber(childrenMatch[1]) : 0,
  };
}

function parseArrivalTime(lines) {
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];

    const englishMatch = line.match(
      /Guest arrival time\s*[：:]?\s*(.+)$/i
    );
    if (englishMatch?.[1]) {
      return normalizeText(englishMatch[1]);
    }

    const japaneseMatch = line.match(
      /ゲストの到着予定時刻\s*[：:]?\s*(.+)$/
    );
    if (japaneseMatch?.[1]) {
      return normalizeText(japaneseMatch[1]);
    }
  }

  return null;
}

function findPrice(lines) {
  const patterns = [
    /(?:JPY|￥|¥)\s*([\d,]+)/i,
    /([\d,]+)\s*円/,
  ];

  for (const line of lines) {
    for (const pattern of patterns) {
      const match = line.match(pattern);
      if (match) return toNumber(match[1]);
    }
  }

  return null;
}

function isReservationNumber(value) {
  return /^\d{8,12}$/.test(normalizeText(value));
}

function isPriceLine(value) {
  return /(?:JPY|￥|¥)\s*[\d,]+|[\d,]+\s*円/i.test(
    normalizeText(value)
  );
}

function extractLatestReservationsSection(lines) {
  const startIndex = lines.findIndex((line) =>
    /^(Latest reservations|最新の予約)$/i.test(line)
  );

  if (startIndex < 0) return lines;

  const endIndex = lines.findIndex(
    (line, index) =>
      index > startIndex &&
      /^(View more|Unanswered messages|もっと見る|未回答のメッセージ)$/i.test(
        line
      )
  );

  return lines.slice(
    startIndex + 1,
    endIndex < 0 ? lines.length : endIndex
  );
}

function parseStructuredReservationCards(lines) {
  const reservations = [];

  for (let index = 0; index < lines.length; index += 1) {
    if (!isReservationNumber(lines[index])) continue;

    const reservationNumber = lines[index];
    const guestName = lines[index - 1] ?? null;
    const roomName = lines[index + 1] ?? null;
    const dateRange = parseDateRange(lines[index + 2] ?? '');

    if (!dateRange) continue;

    const block = [guestName, reservationNumber, roomName];
    let cursor = index + 2;

    while (
      cursor < lines.length &&
      !isReservationNumber(lines[cursor]) &&
      block.length < 10
    ) {
      block.push(lines[cursor]);
      cursor += 1;

      if (isPriceLine(block[block.length - 2] ?? '')) {
        break;
      }
    }

    const stayInfo = parseStayInfo(block);

    let bookedOn = null;
    const priceIndex = block.findIndex(isPriceLine);
    if (priceIndex >= 0 && block[priceIndex + 1]) {
      bookedOn = toIsoDate(block[priceIndex + 1]);
    }

    reservations.push({
      id: `booking-${reservationNumber}`,
      source: 'Booking.com',
      reservationNumber,
      guestName: normalizeText(guestName) || null,
      roomName: normalizeText(roomName) || null,
      checkIn: dateRange.checkIn,
      checkOut: dateRange.checkOut,
      nights: stayInfo.nights,
      adults: stayInfo.adults,
      children: stayInfo.children,
      totalGuests:
        stayInfo.adults === null
          ? null
          : stayInfo.adults + (stayInfo.children ?? 0),
      priceYen: findPrice(block),
      arrivalTime: parseArrivalTime(block),
      bookedOn,
      status: 'confirmed',
      rawBlock: block,
    });
  }

  return reservations;
}

function parseGenericReservations(lines) {
  const reservations = [];

  for (let index = 0; index < lines.length; index += 1) {
    const dateRange = parseDateRange(lines[index]);
    if (!dateRange) continue;

    const windowStart = Math.max(0, index - 12);
    const windowEnd = Math.min(lines.length - 1, index + 14);
    const block = lines.slice(windowStart, windowEnd + 1);

    const numberIndex = block.findIndex(isReservationNumber);
    if (numberIndex < 0) continue;

    const reservationNumber = block[numberIndex];
    const guestName = block[numberIndex - 1] ?? null;
    const roomName = block[numberIndex + 1] ?? null;
    const stayInfo = parseStayInfo(block);

    reservations.push({
      id: `booking-${reservationNumber}`,
      source: 'Booking.com',
      reservationNumber,
      guestName: normalizeText(guestName) || null,
      roomName: normalizeText(roomName) || null,
      checkIn: dateRange.checkIn,
      checkOut: dateRange.checkOut,
      nights: stayInfo.nights,
      adults: stayInfo.adults,
      children: stayInfo.children,
      totalGuests:
        stayInfo.adults === null
          ? null
          : stayInfo.adults + (stayInfo.children ?? 0),
      priceYen: findPrice(block),
      arrivalTime: parseArrivalTime(block),
      bookedOn: null,
      status: 'confirmed',
      rawBlock: block,
    });
  }

  return reservations;
}

function removeDuplicates(reservations) {
  const seen = new Set();

  return reservations.filter((reservation) => {
    const key =
      reservation.reservationNumber ??
      [
        reservation.guestName ?? '',
        reservation.checkIn ?? '',
        reservation.checkOut ?? '',
      ].join('|');

    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function parseReservations(bodyText) {
  const allLines = splitLines(bodyText);
  const latestSection = extractLatestReservationsSection(allLines);

  const structured = parseStructuredReservationCards(latestSection);
  if (structured.length > 0) {
    return removeDuplicates(structured);
  }

  return removeDuplicates(parseGenericReservations(allLines));
}

function createPayload(reservations) {
  return {
    schemaVersion: 1,
    generatedAt: createGeneratedAt(),
    source: 'Booking.com',
    count: reservations.length,
    reservations,
  };
}

function writeJsonAtomic(filePath, data) {
  const temporaryPath = `${filePath}.tmp`;
  const json = `${JSON.stringify(data, null, 2)}\n`;

  fs.writeFileSync(temporaryPath, json, 'utf8');
  fs.renameSync(temporaryPath, filePath);
}

async function waitForUser(rl) {
  console.log('');
  console.log('【Booking.comでの操作】');
  console.log('1. 必要ならログインしてください。');
  console.log('2. ホーム画面または「予約」ページを開いてください。');
  console.log('3. 取得したい予約が画面に表示されていることを確認してください。');
  console.log('4. PowerShellへ戻って Enter を押してください。');
  console.log('');

  await rl.question('予約の表示準備ができたら Enter：');
}

async function main() {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });

  const rl = readline.createInterface({ input, output });
  let context;

  try {
    console.log('Booking.com専用ブラウザを起動しています...');

    context = await chromium.launchPersistentContext(PROFILE_DIR, {
      headless: false,
      viewport: null,
      locale: 'ja-JP',
      timezoneId: 'Asia/Tokyo',
      args: ['--start-maximized'],
    });

    const page = context.pages()[0] ?? (await context.newPage());

    await page.goto(BOOKING_URL, {
      waitUntil: 'domcontentloaded',
      timeout: 60_000,
    });

    await waitForUser(rl);
    await page.waitForTimeout(1500);

    const bodyText = await page.locator('body').innerText();
    const reservations = parseReservations(bodyText);
    const payload = createPayload(reservations);
    const timestamp = createTimestamp();

    const rawTextPath = path.join(
      OUTPUT_DIR,
      `booking_raw_${timestamp}.txt`
    );
    const historyJsonPath = path.join(
      OUTPUT_DIR,
      `reservations_${timestamp}.json`
    );
    const screenshotPath = path.join(
      OUTPUT_DIR,
      `booking_page_${timestamp}.png`
    );

    fs.writeFileSync(rawTextPath, `${bodyText}\n`, 'utf8');
    writeJsonAtomic(historyJsonPath, payload);
    writeJsonAtomic(LATEST_JSON_PATH, payload);

    await page.screenshot({
      path: screenshotPath,
      fullPage: true,
    });

    console.log('');
    console.log('取得が完了しました。');
    console.log(`予約件数：${payload.count}件`);
    console.log(`Flutter読込用：${LATEST_JSON_PATH}`);
    console.log(`履歴JSON：${historyJsonPath}`);
    console.log(`確認用テキスト：${rawTextPath}`);
    console.log(`確認用画像：${screenshotPath}`);

    if (payload.count === 0) {
      console.log('');
      console.log(
        '予約が0件です。予約カードが画面に表示されているか確認してください。'
      );
    } else {
      console.log('');

      for (const [index, reservation] of reservations.entries()) {
        console.log(
          `${index + 1}. ` +
            `${reservation.guestName ?? '氏名不明'} / ` +
            `${reservation.checkIn ?? '?'} ～ ${reservation.checkOut ?? '?'} / ` +
            `大人${reservation.adults ?? '?'}名 ` +
            `子供${reservation.children ?? 0}名 / ` +
            `¥${reservation.priceYen?.toLocaleString('ja-JP') ?? '?'}`
        );
      }
    }

    console.log('');
    console.log(
      'ログイン状態は booking-profile フォルダに保存されます。'
    );
  } catch (error) {
    console.error('');
    console.error('予約取得中にエラーが発生しました。');
    console.error(error);
    process.exitCode = 1;
  } finally {
    rl.close();

    if (context) {
      await context.close();
    }
  }
}

main();
