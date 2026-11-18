import type { RegionInfo } from './provider.ts';

/**
 * Every region the app offers and where its schedule comes from.
 *
 * - `yasno`: Yasno (DTEK) public API — Kyiv city and Dnipropetrovsk oblast (DTEK and CEK).
 * - `gpv`:   community-maintained JSON copies of the operators' hourly schedules ("ГПВ"):
 *            DTEK regions from Baskerville42/outage-data-ua (MIT),
 *            oblenergos from yaroslav2901/OE_OUTAGE_DATA.
 * - `none`:  no open source yet; listed so users see the region is known.
 */
export type RegionSource =
  | { kind: 'yasno'; regionId: number; dsoId: number }
  | { kind: 'gpv'; url: string }
  | { kind: 'none' };

export interface CatalogRegion extends Omit<RegionInfo, 'available'> {
  source: RegionSource;
}

const DTEK = 'https://raw.githubusercontent.com/Baskerville42/outage-data-ua/main/data';
const OE = 'https://raw.githubusercontent.com/yaroslav2901/OE_OUTAGE_DATA/main/data';

const gpv = (base: string, file: string): RegionSource => ({ kind: 'gpv', url: `${base}/${file}.json` });

export const CATALOG: readonly CatalogRegion[] = [
  { id: 'kyiv', name: 'Київ', operator: 'ДТЕК Київські електромережі', source: { kind: 'yasno', regionId: 25, dsoId: 902 } },
  { id: 'kyiv-region', name: 'Київська область', operator: 'ДТЕК Київські регіональні електромережі', source: gpv(DTEK, 'kyiv-region') },
  { id: 'dnipro-dtek', name: 'Дніпропетровська область · ДТЕК', operator: 'ДТЕК Дніпровські електромережі', source: { kind: 'yasno', regionId: 3, dsoId: 301 } },
  { id: 'dnipro-cek', name: 'Дніпропетровська область · ЦЕК', operator: 'ЦЕК', source: { kind: 'yasno', regionId: 3, dsoId: 303 } },
  { id: 'odesa', name: 'Одеська область', operator: 'ДТЕК Одеські електромережі', source: gpv(DTEK, 'odesa') },
  { id: 'cherkasy', name: 'Черкаська область', operator: 'Черкасиобленерго', source: gpv(OE, 'Cherkasyoblenergo') },
  { id: 'chernihiv', name: 'Чернігівська область', operator: 'Чернігівобленерго', source: gpv(OE, 'Chernihivoblenergo') },
  { id: 'ivano-frankivsk', name: 'Івано-Франківська область', operator: 'Прикарпаттяобленерго', source: gpv(OE, 'Prykarpattiaoblenerho') },
  { id: 'kharkiv', name: 'Харківська область', operator: 'Харківобленерго', source: gpv(OE, 'Kharkivoblenerho') },
  { id: 'khmelnytskyi', name: 'Хмельницька область', operator: 'Хмельницькобленерго', source: gpv(OE, 'Khmelnytskoblenerho') },
  { id: 'lviv', name: 'Львівська область', operator: 'Львівобленерго', source: gpv(OE, 'Lvivoblenerho') },
  { id: 'poltava', name: 'Полтавська область', operator: 'Полтаваобленерго', source: gpv(OE, 'Poltavaoblenergo') },
  { id: 'rivne', name: 'Рівненська область', operator: 'Рівнеобленерго', source: gpv(OE, 'Rivneoblenergo') },
  { id: 'ternopil', name: 'Тернопільська область', operator: 'Тернопільобленерго', source: gpv(OE, 'Ternopiloblenerho') },
  { id: 'zakarpattia', name: 'Закарпатська область', operator: 'Закарпаттяобленерго', source: gpv(OE, 'Zakarpattiaoblenerho') },
  { id: 'zaporizhzhia', name: 'Запорізька область', operator: 'Запоріжжяобленерго', source: gpv(OE, 'Zaporizhzhiaoblenergo') },
  { id: 'zhytomyr', name: 'Житомирська область', operator: 'Житомиробленерго', source: gpv(OE, 'Zhytomyroblenergo') },
  { id: 'chernivtsi', name: 'Чернівецька область', operator: 'Чернівціобленерго', source: { kind: 'none' } },
  { id: 'donetsk', name: 'Донецька область', operator: 'ДТЕК Донецькі електромережі', source: { kind: 'none' } },
  { id: 'kherson', name: 'Херсонська область', operator: 'Херсонобленерго', source: { kind: 'none' } },
  { id: 'kirovohrad', name: 'Кіровоградська область', operator: 'Кіровоградобленерго', source: { kind: 'none' } },
  { id: 'mykolaiv', name: 'Миколаївська область', operator: 'Миколаївобленерго', source: { kind: 'none' } },
  { id: 'sumy', name: 'Сумська область', operator: 'Сумиобленерго', source: { kind: 'none' } },
  { id: 'vinnytsia', name: 'Вінницька область', operator: 'Вінницяобленерго', source: { kind: 'none' } },
  { id: 'volyn', name: 'Волинська область', operator: 'Волиньобленерго', source: { kind: 'none' } },
];

export function regionInfo(r: CatalogRegion): RegionInfo {
  return { id: r.id, name: r.name, operator: r.operator, available: r.source.kind !== 'none' };
}

export function findRegion(id: string): CatalogRegion | undefined {
  return CATALOG.find((r) => r.id === id);
}
