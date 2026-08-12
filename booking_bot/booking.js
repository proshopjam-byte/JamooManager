'use strict';

const fs = require('fs');
const path = require('path');
const readline = require('readline/promises');
const { stdin: input, stdout: output } = require('process');

const BOOKING_URL = 'https://admin.booking.com';
const PROFILE_DIR = path.join(__dirname, 'booking-profile');
const OUTPUT_DIR = path.join(__dirname, 'output');
const LATEST_JSON_PATH = path.join(
  OUTPUT_DIR,
  'reservations_latest.json'
);

const ENGLISH_MONTHS = {
  jan: 1,
  feb: 2,
  mar: 3,
  apr: 4,
  may: 5,
  jun: 6,
  jul: 7,
  aug: 8,
  sep: 9,
  oct: 10,
  nov: 11,
  dec: 12,
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

function toNumber(value) {
  if (value === null || value === undefined) {
    return null;
  }

  const cleaned = String(value).replace(/[^\d-]/g, '');

  if (!cleaned || cleaned === '-') {
    return null;
  }

  const number = Number(cleaned);
  return Number.isFinite(number) ? number : null;
}

function formatJstDate(date = new Date()) {
  return new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'Asia/Tokyo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
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

  return (
    `${parts.year}-${parts.month}-${parts.day}_` +
    `${parts.hour}-${parts.minute}-${parts.second}`
  );
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
  const separator = '[–—－〜～~-]';

  const japanesePattern = new RegExp(
    `(\\d{4}年\\s*\\d{1,2}月\\s*\\d{1,2}日)` +
      `\\s*${separator}\\s*` +
      `(\\d{4}年\\s*\\d{1,2}月\\s*\\d{1,2}日)`
  );

  const englishDate =
    '(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)' +
    '\\s+\\d{1,2},\\s*\\d{4}';

  const englishPattern = new RegExp(
    `(${englishDate})\\s*${separator}\\s*(${englishDate})`,
    'i'
  );

  const match =
    text.match(japanesePattern) ??
    text.match(englishPattern);

  if (!match) {
    return null;
  }

  const checkIn = toIsoDate(match[1]);
  const checkOut = toIsoDate(match[2]);

  if (!checkIn || !checkOut) {
    return null;
  }

  return {
    checkIn,
    checkOut,
  };
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
    children: childrenMatch
      ? toNumber(childrenMatch[1])
      : 0,
  };
}

function parseArrivalTime(lines) {
  for (const line of lines) {
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

      if (match) {
        return toNumber(match[1]);
      }
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

function isCancelledBlock(lines) {
  return lines.some((line) =>
    /\b(cancelled|canceled|cancellation)\b|キャンセル/i.test(
      line
    )
  );
}

function extractArrivalsArea(lines) {
  const latestIndex = lines.findIndex((line) =>
    /^(Latest reservations|最新の予約)$/i.test(line)
  );

  if (latestIndex < 0) {
    return lines;
  }

  let reservationsHeadingIndex = -1;

  for (
    let index = latestIndex - 1;
    index >= 0;
    index -= 1
  ) {
    if (/^(Reservations|予約)$/i.test(lines[index])) {
      reservationsHeadingIndex = index;
      break;
    }
  }

  const startIndex =
    reservationsHeadingIndex >= 0
      ? reservationsHeadingIndex + 1
      : 0;

  return lines.slice(startIndex, latestIndex);
}

function findNearestReservationNumberIndex(
  lines,
  dateLineIndex
) {
  for (let distance = 1; distance <= 6; distance += 1) {
    const beforeIndex = dateLineIndex - distance;

    if (
      beforeIndex >= 0 &&
      isReservationNumber(lines[beforeIndex])
    ) {
      return beforeIndex;
    }

    const afterIndex = dateLineIndex + distance;

    if (
      afterIndex < lines.length &&
      isReservationNumber(lines[afterIndex])
    ) {
      return afterIndex;
    }
  }

  return -1;
}

function createReservationFromDateLine(
  lines,
  dateLineIndex
) {
  const dateRange = parseDateRange(lines[dateLineIndex]);

  if (!dateRange) {
    return null;
  }

  const numberIndex = findNearestReservationNumberIndex(
    lines,
    dateLineIndex
  );

  if (numberIndex < 0) {
    return null;
  }

  const reservationNumber = lines[numberIndex];
  const guestName = lines[numberIndex - 1] ?? null;
  const roomName = lines[numberIndex + 1] ?? null;

  const blockStart = Math.max(0, numberIndex - 1);
  const block = [];

  for (
    let index = blockStart;
    index < lines.length && block.length < 14;
    index += 1
  ) {
    if (
      index > numberIndex &&
      isReservationNumber(lines[index])
    ) {
      break;
    }

    if (
      /^(View more|Unanswered messages|もっと見る|未回答のメッセージ)$/i.test(
        lines[index]
      )
    ) {
      break;
    }

    block.push(lines[index]);

    if (
      isPriceLine(lines[index - 1] ?? '') &&
      toIsoDate(lines[index])
    ) {
      break;
    }
  }

  const stayInfo = parseStayInfo(block);
  const priceIndex = block.findIndex(isPriceLine);

  let bookedOn = null;

  if (priceIndex >= 0 && block[priceIndex + 1]) {
    bookedOn = toIsoDate(block[priceIndex + 1]);
  }

  return {
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
    status: isCancelledBlock(block)
      ? 'cancelled'
      : 'confirmed',
    rawBlock: block,
  };
}

function parseReservationsFromLines(lines) {
  const reservations = [];

  for (
    let index = 0;
    index < lines.length;
    index += 1
  ) {
    if (!parseDateRange(lines[index])) {
      continue;
    }

    const reservation = createReservationFromDateLine(
      lines,
      index
    );

    if (reservation) {
      reservations.push(reservation);
    }
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

    if (seen.has(key)) {
      return false;
    }

    seen.add(key);
    return true;
  });
}

function parseTodayCheckIns(
  bodyText,
  targetDate = formatJstDate()
) {
  const allLines = splitLines(bodyText);
  const arrivalsArea = extractArrivalsArea(allLines);

  const candidates = removeDuplicates([
    ...parseReservationsFromLines(arrivalsArea),
    ...parseReservationsFromLines(allLines),
  ]);

  return candidates.filter(
    (reservation) =>
      reservation.checkIn === targetDate &&
      reservation.status !== 'cancelled'
  );
}

function parseUpcomingReservations(
  bodyText,
  targetDate = formatJstDate()
) {
  const allLines = splitLines(bodyText);
  const candidates = removeDuplicates(
    parseReservationsFromLines(allLines)
  );

  return candidates.filter(
    (reservation) =>
      reservation.checkIn !== null &&
      reservation.checkIn >= targetDate &&
      reservation.status !== 'cancelled'
  );
}

function parseReservationListBody(bodyText, targetDate = formatJstDate()) {
  const lines = splitLines(bodyText);
  const reservations = [];
  const englishDatePattern =
    /\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},\s*\d{4}\b/gi;

  for (let index = 1; index < lines.length; index += 1) {
    const detailLine = lines[index];
    const dateMatches = [...detailLine.matchAll(englishDatePattern)];

    if (dateMatches.length < 2) {
      continue;
    }

    const checkIn = toIsoDate(dateMatches[0][0]);
    const checkOut = toIsoDate(dateMatches[1][0]);

    if (!checkIn || !checkOut) {
      continue;
    }

    const firstDateIndex = dateMatches[0].index ?? 0;
    const secondDateEnd =
      (dateMatches[1].index ?? 0) + dateMatches[1][0].length;
    const guestInfo = normalizeText(detailLine.slice(0, firstDateIndex));
    const roomName = normalizeText(detailLine.slice(secondDateEnd));
    const block = [lines[index - 1], detailLine];

    for (
      let lookAhead = index + 1;
      lookAhead < lines.length && lookAhead <= index + 10;
      lookAhead += 1
    ) {
      block.push(lines[lookAhead]);

      if (/\b\d{8,12}\b/.test(lines[lookAhead])) {
        break;
      }
    }

    const joinedBlock = block.join(' ');
    const numberMatch = joinedBlock.match(/\b(\d{8,12})\b/);

    if (!numberMatch) {
      continue;
    }

    const stayInfo = parseStayInfo([guestInfo]);
    const moneyLine = block.find((line) =>
      /(?:¥|￥|JPY|ﾂ･)\s*[\d,]+|\d{1,3}(?:,\d{3})+/.test(line)
    );
    const reservationNumber = numberMatch[1];
    const status = isCancelledBlock(block)
      ? 'cancelled'
      : 'confirmed';

    reservations.push({
      id: `booking-${reservationNumber}`,
      source: 'Booking.com',
      reservationNumber,
      guestName: normalizeText(lines[index - 1]) || null,
      roomName: roomName || null,
      checkIn,
      checkOut,
      nights: Math.max(
        0,
        Math.round(
          (Date.parse(`${checkOut}T00:00:00Z`) -
            Date.parse(`${checkIn}T00:00:00Z`)) /
            86_400_000
        )
      ),
      adults: stayInfo.adults,
      children: stayInfo.children,
      totalGuests:
        stayInfo.adults === null
          ? null
          : stayInfo.adults + (stayInfo.children ?? 0),
      priceYen: moneyLine ? toNumber(moneyLine) : null,
      arrivalTime: null,
      bookedOn: toIsoDate(block[2]),
      status,
      rawBlock: block,
    });
  }

  return removeDuplicates(reservations).filter(
    (reservation) =>
      reservation.checkIn >= targetDate &&
      reservation.status !== 'cancelled'
  );
}

function parseReservationTableCells(cells) {
  if (!Array.isArray(cells) || cells.length < 8) {
    return null;
  }

  const normalized = cells.map(normalizeText);
  const checkIn = toIsoDate(normalized[1]);
  const checkOut = toIsoDate(normalized[2]);
  const reservationNumber = normalized
    .slice()
    .reverse()
    .find(isReservationNumber);

  if (!checkIn || !checkOut || !reservationNumber) {
    return null;
  }

  const guestLines = String(cells[0] ?? '')
    .replace(/\r/g, '')
    .split('\n')
    .map(normalizeText)
    .filter(Boolean);
  const guestName = guestLines.find(
    (line) =>
      !/^Genius$/i.test(line) &&
      !/\b\d+\s*(?:adult|adults|child|children)\b/i.test(line)
  );
  const stayInfo = parseStayInfo(guestLines);
  const statusText = normalized[5] ?? '';

  return {
    id: `booking-${reservationNumber}`,
    source: 'Booking.com',
    reservationNumber,
    guestName: guestName || null,
    roomName: normalized[3] || null,
    checkIn,
    checkOut,
    nights: Math.max(
      0,
      Math.round(
        (Date.parse(`${checkOut}T00:00:00Z`) -
          Date.parse(`${checkIn}T00:00:00Z`)) /
          86_400_000
      )
    ),
    adults: stayInfo.adults,
    children: stayInfo.children,
    totalGuests:
      stayInfo.adults === null
        ? null
        : stayInfo.adults + (stayInfo.children ?? 0),
    priceYen: toNumber(normalized[6]),
    arrivalTime: null,
    bookedOn: toIsoDate(normalized[4]),
    status: /\b(cancelled|canceled)\b|キャンセル/i.test(statusText)
      ? 'cancelled'
      : 'confirmed',
    rawBlock: normalized,
  };
}

async function readReservationTable(container, targetDate) {
  const rows = container.locator('tr, [role="row"]');
  const reservations = [];

  for (let index = 0; index < (await rows.count()); index += 1) {
    const cells = await rows
      .nth(index)
      .locator('td, [role="cell"], [role="gridcell"]')
      .allInnerTexts();
    const reservation = parseReservationTableCells(cells);

    if (
      reservation &&
      reservation.checkIn >= targetDate &&
      reservation.status !== 'cancelled'
    ) {
      reservations.push(reservation);
    }
  }

  return removeDuplicates(reservations);
}

async function selectReservationPage(context, targetDate) {
  let best = null;

  const pages = context.pages();

  for (const [pageIndex, candidate] of pages.entries()) {
    try {
      await candidate.waitForLoadState('domcontentloaded', {
        timeout: 10_000,
      });
      const tableReservations = [];

      for (const frame of candidate.frames()) {
        try {
          tableReservations.push(
            ...(await readReservationTable(frame, targetDate))
          );
        } catch (_) {
          // Continue with other frames.
        }
      }

      const bodyText = await candidate.locator('body').innerText();
      const bodyReservations = parseUpcomingReservations(
        bodyText,
        targetDate
      );
      const listReservations = parseReservationListBody(
        bodyText,
        targetDate
      );
      const reservations = removeDuplicates([
        ...tableReservations,
        ...listReservations,
        ...bodyReservations,
      ]);
      const url = candidate.url();
      const title = await candidate.title();
      let reservationUrlBonus = 0;

      try {
        reservationUrlBonus = /reservation|booking/i.test(
          new URL(url).pathname
        )
          ? 10_000
          : 0;
      } catch (_) {
        // Keep the URL bonus at zero for non-standard URLs.
      }
      const score =
        reservationUrlBonus +
        tableReservations.length * 100 +
        reservations.length +
        pageIndex;

      console.log(
        `確認タブ${pageIndex + 1}: 表${tableReservations.length}件 / ` +
          `候補${reservations.length}件 / ${title} / ${url}`
      );

      if (!best || score > best.score) {
        best = {
          page: candidate,
          bodyText,
          reservations,
          score,
        };
      }
    } catch (_) {
      // Ignore transient or already closed tabs.
    }
  }

  return best;
}

function mealPlanFromDetail(bodyText) {
  const text = normalizeText(bodyText);
  if (/\bonbreakfast\b/i.test(text)) {
    return {
      planName: 'onbreakfast',
      hasBreakfast: true,
      hasDinner: false,
    };
  }
  if (/\bstandard\s+rate\b/i.test(text)) {
    return {
      planName: 'Standard Rate',
      hasBreakfast: false,
      hasDinner: false,
    };
  }
  return {
    planName: null,
    hasBreakfast: null,
    hasDinner: null,
  };
}

function mealPlanFromPrice(reservation) {
  const guests =
    reservation.totalGuests ??
    ((reservation.adults ?? 0) + (reservation.children ?? 0));
  const price = reservation.priceYen;
  const nights = reservation.nights ?? 1;

  if (!price || !guests || guests < 1 || nights < 1) {
    return {
      planName: null,
      hasBreakfast: null,
      hasDinner: false,
    };
  }

  const pricePerGuestPerNight = Math.round(price / guests / nights);
  const hasBreakfast =
    guests === 1
      ? pricePerGuestPerNight > 10_800
      : pricePerGuestPerNight >= 9_000;

  return {
    planName: hasBreakfast
      ? `料金判定・朝食付き（1人1泊あたり¥${pricePerGuestPerNight.toLocaleString('ja-JP')}）`
      : `料金判定・素泊まり（1人1泊あたり¥${pricePerGuestPerNight.toLocaleString('ja-JP')}）`,
    hasBreakfast,
    hasDinner: false,
  };
}

async function enrichMealPlans(context, reservationPage, reservations) {
  const enriched = [];

  console.log('Booking.comの食事プランを確認しています...');

  for (const reservation of reservations) {
    const number = reservation.reservationNumber;
    let meal = {
      planName: null,
      hasBreakfast: null,
      hasDinner: null,
    };

    if (number) {
      try {
        const link = reservationPage
          .locator('a')
          .filter({ hasText: number })
          .first();
        const href = await link.getAttribute('href');

        if (href) {
          const detailPage = await context.newPage();
          try {
            await detailPage.goto(new URL(href, reservationPage.url()).href, {
              waitUntil: 'domcontentloaded',
              timeout: 60_000,
            });
            await detailPage.waitForTimeout(800);
            meal = mealPlanFromDetail(
              await detailPage.locator('body').innerText()
            );
          } finally {
            await detailPage.close();
          }
        }
      } catch (_) {
        // Keep the meal plan unset when a detail page cannot be read.
      }
    }

    if (meal.planName === null) {
      meal = mealPlanFromPrice(reservation);
    }

    console.log(
      `${reservation.guestName ?? number ?? '予約'}: ` +
        `${meal.planName ?? '食事プラン未設定'}`
    );
    enriched.push({ ...reservation, ...meal });
  }

  return enriched;
}

function createPayload(
  reservations,
  targetDate
) {
  return {
    schemaVersion: 1,
    generatedAt: createGeneratedAt(),
    source: 'Booking.com',
    scope: 'upcoming_reservations',
    targetDate,
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

async function waitForUser(rl, targetDate) {
  console.log('');
  console.log('【Booking.comでの操作】');
  console.log('取得対象は今日から1年先までの将来予約です。');
  console.log(`開始日：${targetDate}（日本時間）`);
  console.log('');
  console.log('1. 必要ならログインしてください。');
  console.log('2. 「Reservations／予約」を開いてください。');
  console.log(
    '3. チェックイン日を今日から1年先までにして、予約一覧を表示してください。'
  );
  console.log(
    '4. 表示件数を最大にし、一覧の最後までスクロールしてください。'
  );
  console.log(
    '5. 一覧が複数ページの場合は、取得したい予約が表示されるページを開いてください。'
  );
  console.log('6. PowerShellへ戻って Enter を押してください。');
  console.log('');

  await rl.question(
    '将来予約一覧の準備ができたら Enter：'
  );
}

async function main() {
  const { chromium } = require('playwright');

  fs.mkdirSync(OUTPUT_DIR, {
    recursive: true,
  });

  const targetDate = formatJstDate();
  const rl = readline.createInterface({
    input,
    output,
  });

  let context;

  try {
    console.log(
      'Booking.com専用ブラウザを起動しています...'
    );

    context =
      await chromium.launchPersistentContext(
        PROFILE_DIR,
        {
          headless: false,
          viewport: null,
          locale: 'ja-JP',
          timezoneId: 'Asia/Tokyo',
          args: ['--start-maximized'],
        }
      );

    const page =
      context.pages()[0] ??
      (await context.newPage());

    await page.goto(BOOKING_URL, {
      waitUntil: 'domcontentloaded',
      timeout: 60_000,
    });

    await waitForUser(rl, targetDate);
    await page.waitForTimeout(1500);

    const selected = await selectReservationPage(
      context,
      targetDate
    );

    if (!selected) {
      throw new Error('予約一覧を表示しているタブを確認できませんでした。');
    }

    const selectedPage = selected.page;
    const bodyText = selected.bodyText;
    const reservations = await enrichMealPlans(
      context,
      selectedPage,
      selected.reservations
    );

    console.log(
      `読取対象: ${await selectedPage.title()} / ${selectedPage.url()}`
    );

    if (reservations.length === 0) {
      throw new Error(
        '予約一覧から予約を解析できなかったため、既存データは更新しませんでした。'
      );
    }

    const payload = createPayload(
      reservations,
      targetDate
    );

    const timestamp = createTimestamp();

    const rawTextPath = path.join(
      OUTPUT_DIR,
      `booking_raw_${timestamp}.txt`
    );

    const historyJsonPath = path.join(
      OUTPUT_DIR,
      `upcoming_reservations_${timestamp}.json`
    );

    const screenshotPath = path.join(
      OUTPUT_DIR,
      `booking_page_${timestamp}.png`
    );

    fs.writeFileSync(
      rawTextPath,
      `${bodyText}\n`,
      'utf8'
    );

    writeJsonAtomic(historyJsonPath, payload);
    writeJsonAtomic(LATEST_JSON_PATH, payload);

    await selectedPage.screenshot({
      path: screenshotPath,
      fullPage: true,
    });

    console.log('');
    console.log('将来予約の取得が完了しました。');
    console.log(`開始日：${targetDate}`);
    console.log(`将来予約：${payload.count}件`);
    console.log(
      `Flutter読込用：${LATEST_JSON_PATH}`
    );
    console.log(`履歴JSON：${historyJsonPath}`);
    console.log(
      `確認用テキスト：${rawTextPath}`
    );
    console.log(
      `確認用画像：${screenshotPath}`
    );

    if (payload.count === 0) {
      console.log('');
      console.log(
        '本日のチェックイン予定は0件です。'
      );
    } else {
      console.log('');

      for (
        const [index, reservation]
        of reservations.entries()
      ) {
        console.log(
          `${index + 1}. ` +
            `${reservation.guestName ?? '氏名不明'} / ` +
            `${reservation.checkIn ?? '?'} ～ ` +
            `${reservation.checkOut ?? '?'} / ` +
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
    console.error(
      '将来予約の取得中にエラーが発生しました。'
    );
    console.error(error);
    process.exitCode = 1;
  } finally {
    rl.close();

    if (context) {
      await context.close();
    }
  }
}

if (require.main === module) {
  main();
}

module.exports = {
  formatJstDate,
  parseTodayCheckIns,
  parseUpcomingReservations,
  parseReservationListBody,
  parseReservationTableCells,
  mealPlanFromDetail,
  mealPlanFromPrice,
};
