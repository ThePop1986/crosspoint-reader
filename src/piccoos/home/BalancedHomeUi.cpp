#include "piccoos/home/BalancedHomeUi.h"

// F-1: guard against future MAX_BOOKS > MAX_COVERS (mirrors CoverGridHomeUi.h:20).
static_assert(BalancedHomeUi::MAX_BOOKS <= HomeCoverCache::MAX_COVERS,
              "increase HomeCoverCache::MAX_COVERS or reduce BalancedHomeUi::MAX_BOOKS");

#include <GfxRenderer.h>
#include <HalPowerManager.h>
#include <I18n.h>
#include <Logging.h>

#include <algorithm>
#include <array>
#include <string>

#include "MappedInputManager.h"
#include "components/UITheme.h"
#include "components/icons/blocks.h"
#include "components/icons/folder.h"
#include "components/icons/library.h"
#include "components/icons/settings2.h"
#include "components/icons/transfer.h"
#include "fontIds.h"
#include "util/BookProgress.h"

namespace fui = freeink::ui;

// Layout constants (480×800 portrait, spec §3).
// F-2: cover dimensions sourced from BalancedHomeUi class constants (single source of truth).
namespace layout {
constexpr int MARGIN = 24;
constexpr int STATUS_H = 32;

// Hero cover slot — dimensions from class constants (D-029).
constexpr int HERO_X = 24;
constexpr int HERO_Y = 52;
constexpr int HERO_W = BalancedHomeUi::HERO_WIDTH;    // 200
constexpr int HERO_H = BalancedHomeUi::HERO_HEIGHT;   // 300
// Focus frame: 3px border with 6px offset
constexpr int HERO_FRAME_X = 18;
constexpr int HERO_FRAME_Y = 46;
constexpr int HERO_FRAME_W = 212;
constexpr int HERO_FRAME_H = 312;

// F-5: Hero hit zone (spec §3: x 18–456, y 46–358). Shared by render and hit-test.
constexpr int HERO_HIT_X = HERO_FRAME_X;       // 18
constexpr int HERO_HIT_Y = HERO_FRAME_Y;       // 46
constexpr int HERO_HIT_W = 456 - HERO_FRAME_X; // 438 (18..456)
constexpr int HERO_HIT_H = HERO_FRAME_H;       // 312 (46..358)

// Info column to the right of hero
constexpr int INFO_X = 248;
constexpr int INFO_W = 208;
constexpr int TITLE_Y = 52;
constexpr int PROGRESS_BASE = 336;
constexpr int PROG_BAR_Y = 346;
constexpr int PROG_BAR_H = 6;

// Section header y=396 (baseline)
constexpr int SECTION_BASE = 396;

// Recent covers: y=412; x positions 24, 176, 328 — dimensions from class constants (D-029).
constexpr int RECENT_Y = 412;
constexpr int RECENT_X0 = 24;
constexpr int RECENT_X1 = 176;
constexpr int RECENT_X2 = 328;
constexpr int RECENT_W = BalancedHomeUi::RECENT_WIDTH;    // 128
constexpr int RECENT_H = BalancedHomeUi::RECENT_HEIGHT;   // 192
constexpr int RECENT_STEP = 152;    // spacing between left edges
constexpr int RECENT_PROG_Y = 608;
constexpr int RECENT_PROG_H = 3;
constexpr int RECENT_TITLE_LINE1 = 634;
constexpr int RECENT_TITLE_LINE2 = 652;

// F-5: Recent hit zone (spec §3: slot x, y 412–660). Covers + title text below.
constexpr int RECENT_HIT_Y = RECENT_Y;         // 412
constexpr int RECENT_HIT_H = 660 - RECENT_Y;  // 248 (412..660)

// Bottom panel
constexpr int PANEL_LINE_Y = 711;
constexpr int PANEL_TOP = 712;
constexpr int PANEL_ICON_Y = 732;
constexpr int PANEL_ICON_SIZE = 24;
constexpr int PANEL_LABEL_BASE = 782;
}  // namespace layout

BalancedHomeUi::BalancedHomeUi(GfxRenderer& renderer) : renderer(renderer), coverCache(renderer) {
  bookProgress.fill(-1);
}

void BalancedHomeUi::begin(const std::vector<RecentBook>& bks, CoverGridHomeUi::SlotTab tab,
                           bool hasContinueReading) {
  books = &bks;
  slotTab = tab;
  hasContinueReading_ = hasContinueReading;
  coverCache.begin();
  thumbHeightChanged_ = true;

  // R1: compute visible_ and showAllBooks_ from full list before HomeActivity resizes recentBooks.
  const int sz = static_cast<int>(bks.size());
  showAllBooks_ = sz >= MAX_BOOKS;  // spec §3: show «Все книги ›» if ≥ 4 found before trim
  visible_ = hasContinueReading ? std::min(sz, 4) : std::min(sz, 3);

  // Cache reading progress for all book slots; loadBookProgress reads from SD.
  bookProgress.fill(-1);
  for (int i = 0; i < static_cast<int>(bks.size()) && i < MAX_BOOKS; ++i) {
    bookProgress[i] = loadBookProgress(bks[i].path);
  }

  refreshCoverPaths();
}

void BalancedHomeUi::refreshCoverPaths() {
  if (books == nullptr) return;
  for (int i = 0; i < static_cast<int>(books->size()) && i < MAX_BOOKS; ++i) {
    // C-1/F-2: use thumbHeightFor which respects hasContinueReading_ (no thumb_300 without history).
    const int h = thumbHeightFor(i);
    const auto& book = (*books)[i];
    coverPaths[i] = book.coverBmpPath.empty() ? std::string{} : UITheme::getCoverThumbPath(book.coverBmpPath, h);
  }
}

bool BalancedHomeUi::takeThumbHeightChanged() {
  if (thumbHeightChanged_) {
    thumbHeightChanged_ = false;
    return true;
  }
  return false;
}

int BalancedHomeUi::selectedAction(const MappedInputManager& input) {
  // F-1: panel always works; guard only nullptr (not empty).
  if (books == nullptr) return -1;

  const int booksCount = static_cast<int>(books->size());
  const int selectorBase = booksCount;

  if (!books->empty()) {
    if (hasContinueReading_) {
      // State 3: hero tap (spec §3: x 18–456, y 46–358).
      int heroRow = -1;
      const auto heroTouch = input.rowTouch(heroRow, layout::HERO_HIT_Y, layout::HERO_HIT_H, 1,
                                            layout::HERO_HIT_X, layout::HERO_HIT_X + layout::HERO_HIT_W,
                                            layout::HERO_HIT_H);
      if (heroTouch == MappedInputManager::RowTouch::Tap) return 0;
    } else {
      // State 2: "Начните читать" card tap → Library (C-1: tappable, not in selectorIndex).
      int cardRow = -1;
      const auto cardTouch = input.rowTouch(cardRow, layout::HERO_HIT_Y, layout::HERO_HIT_H, 1,
                                            layout::HERO_HIT_X, layout::HERO_HIT_X + layout::HERO_HIT_W,
                                            layout::HERO_HIT_H);
      if (cardTouch == MappedInputManager::RowTouch::Tap) return selectorBase + 1;  // Library
    }

    // Recent covers (spec §3: slot x, y 412–660).
    // State 3: recents start at books[1]; state 2: recents start at books[0].
    const int recentStart = hasContinueReading_ ? 1 : 0;
    const int recentCount = hasContinueReading_ ? std::min(booksCount - 1, 3) : std::min(booksCount, 3);
    if (recentCount > 0) {
      int recentCol = -1;
      const auto recentTouch = input.colTouch(recentCol, layout::RECENT_X0, layout::RECENT_STEP, recentCount,
                                              layout::RECENT_HIT_Y, layout::RECENT_HIT_Y + layout::RECENT_HIT_H);
      if (recentTouch == MappedInputManager::RowTouch::Tap && recentCol >= 0)
        return recentStart + recentCol;
    }

    // "Все книги ›" link: only when displayed (showAllBooks_ set before resize; spec §3).
    if (showAllBooks_) {
      const int screenW = renderer.getScreenWidth();
      int allBooksRow = -1;
      const auto allBooksTouch = input.rowTouch(allBooksRow, layout::SECTION_BASE - 18, 24, 1,
                                                screenW - 80, screenW);
      if (allBooksTouch == MappedInputManager::RowTouch::Tap) return selectorBase + 1;  // Library
    }
  }

  // Bottom panel — always active (F-1).
  const int itemCount = (slotTab != CoverGridHomeUi::SlotTab::NONE) ? 5 : 4;
  const int screenW = renderer.getScreenWidth();
  const int cellW = screenW / itemCount;
  int panelCol = -1;
  const auto panelTouch =
      input.colTouch(panelCol, 0, cellW, itemCount, layout::PANEL_TOP, renderer.getScreenHeight());
  if (panelTouch == MappedInputManager::RowTouch::Tap && panelCol >= 0) return selectorBase + panelCol;

  return -1;
}

void BalancedHomeUi::drawStatusBar() {
  const int screenW = renderer.getScreenWidth();
  GUI.drawHeader(renderer, Rect{0, 0, screenW, layout::STATUS_H}, nullptr, nullptr, false);
}

// State 3: current book with thumb_300 in hero slot.
void BalancedHomeUi::drawHeroSlot() {
  if (books == nullptr || books->empty()) return;
  const auto& hero = (*books)[0];

  // Focus frame (3px, 6px offset from cover slot)
  if (selected == 0) {
    for (int t = 0; t < 3; ++t) {
      renderer.drawRect(layout::HERO_FRAME_X - t, layout::HERO_FRAME_Y - t,
                        layout::HERO_FRAME_W + 2 * t, layout::HERO_FRAME_H + 2 * t);
    }
  }

  coverCache.paint(fui::Rect{layout::HERO_X, layout::HERO_Y, layout::HERO_W, layout::HERO_H}, 0, coverPaths[0]);

  // Title (18 bold, up to 4 lines, line height 26)
  const auto titleLines =
      renderer.wrappedText(NOTOSANS_18_FONT_ID, hero.title.c_str(), layout::INFO_W, 4, EpdFontFamily::BOLD);
  int textY = layout::TITLE_Y;
  for (const auto& line : titleLines) {
    renderer.drawText(NOTOSANS_18_FONT_ID, layout::INFO_X, textY, line.c_str(), true, EpdFontFamily::BOLD);
    textY += 26;
  }

  // Author (16 regular, up to 2 lines)
  if (!hero.author.empty()) {
    textY += 10;
    const auto authorLines =
        renderer.wrappedText(NOTOSANS_16_FONT_ID, hero.author.c_str(), layout::INFO_W, 2, EpdFontFamily::REGULAR);
    for (const auto& line : authorLines) {
      renderer.drawText(NOTOSANS_16_FONT_ID, layout::INFO_X, textY, line.c_str(), true, EpdFontFamily::REGULAR);
      textY += renderer.getLineHeight(NOTOSANS_16_FONT_ID);
    }
  }

  // Progress % (16 bold, baseline 336)
  const int pct = bookProgress[0];
  if (pct >= 0) {
    const auto pctStr = std::to_string(pct) + "%";
    renderer.drawText(NOTOSANS_16_FONT_ID, layout::INFO_X, layout::PROGRESS_BASE, pctStr.c_str(), true,
                      EpdFontFamily::BOLD);
    renderer.drawRect(layout::INFO_X, layout::PROG_BAR_Y, layout::INFO_W, layout::PROG_BAR_H);
    const int fillW = layout::INFO_W * pct / 100;
    if (fillW > 0) renderer.fillRect(layout::INFO_X, layout::PROG_BAR_Y, fillW, layout::PROG_BAR_H);
  }
}

// State 2: no reading history, books exist. Card tappable → Library (C-1: not in button focus).
void BalancedHomeUi::drawStartReadingCard() {
  renderer.drawRect(layout::HERO_X, layout::HERO_Y, layout::HERO_W, layout::HERO_H);
  UITheme::drawCenteredWrappedText(renderer,
      Rect{layout::HERO_X + 4, layout::HERO_Y + 4, layout::HERO_W - 8, (layout::HERO_H - 8) / 2},
      NOTOSANS_16_FONT_ID, tr(STR_PICCOOS_START_READING), 2);
  UITheme::drawCenteredWrappedText(renderer,
      Rect{layout::HERO_X + 4, layout::HERO_Y + (layout::HERO_H) / 2, layout::HERO_W - 8, layout::HERO_H / 2},
      NOTOSANS_14_FONT_ID, tr(STR_OPEN_LIBRARY), 2);
}

// State 1: no books at all. Focus = Transfer (set by HomeActivity::onEnter, C-1).
void BalancedHomeUi::drawAddBooksCard() {
  renderer.drawRect(layout::HERO_X, layout::HERO_Y, layout::HERO_W, layout::HERO_H);
  UITheme::drawCenteredWrappedText(renderer,
      Rect{layout::HERO_X + 4, layout::HERO_Y + 4, layout::HERO_W - 8, layout::HERO_H - 8},
      NOTOSANS_16_FONT_ID, tr(STR_ADD_BOOKS), 4);
}

void BalancedHomeUi::drawRecentSection() {
  if (books == nullptr || books->empty()) return;

  // State 2 (!hasContinueReading_): books[0..N-1] are library books; use as recents[0..N-1].
  // State 3 (hasContinueReading_): books[1..N-1] are recents; books[0] is hero.
  const int recentStart = hasContinueReading_ ? 1 : 0;
  const int recentCount = hasContinueReading_
      ? std::min(static_cast<int>(books->size()) - 1, 3)
      : std::min(static_cast<int>(books->size()), 3);
  if (recentCount <= 0) return;

  // C-2: "Новые книги" header when no reading history; "Недавние" otherwise.
  const StrId headerId = hasContinueReading_ ? StrId::STR_RECENT : StrId::STR_NEW_BOOKS;
  renderer.drawText(NOTOSANS_16_FONT_ID, layout::MARGIN, layout::SECTION_BASE, I18n::getInstance().get(headerId), true,
                    EpdFontFamily::BOLD);

  // "Все книги ›" (14 regular, right-aligned at x=456; hidden when < 4 books before trim; spec §3).
  if (showAllBooks_) {
    const char* allLabel = tr(STR_ALL_BOOKS);
    const int allW = renderer.getTextWidth(NOTOSANS_14_FONT_ID, allLabel);
    renderer.drawText(NOTOSANS_14_FONT_ID, 456 - allW, layout::SECTION_BASE, allLabel, true,
                      EpdFontFamily::REGULAR);
  }

  constexpr int recentX[3] = {layout::RECENT_X0, layout::RECENT_X1, layout::RECENT_X2};

  for (int i = 0; i < recentCount; ++i) {
    const int bookIdx = recentStart + i;
    const int x = recentX[i];
    const fui::Rect slot{static_cast<int16_t>(x), layout::RECENT_Y, layout::RECENT_W, layout::RECENT_H};

    // Focus frame (3px, 4px offset)
    if (selected == bookIdx) {
      for (int t = 0; t < 3; ++t) {
        renderer.drawRect(x - 4 - t, layout::RECENT_Y - 4 - t,
                          layout::RECENT_W + 2 * (4 + t), layout::RECENT_H + 2 * (4 + t));
      }
    }

    coverCache.paint(slot, static_cast<size_t>(bookIdx), coverPaths[static_cast<size_t>(bookIdx)]);

    // C-2: no progress bars for state 2 (no reading history → no progress recorded).
    const int pct = hasContinueReading_ ? bookProgress[bookIdx] : -1;
    if (pct > 0) {
      const int barW = layout::RECENT_W * pct / 100;
      renderer.fillRect(x, layout::RECENT_PROG_Y, barW, layout::RECENT_PROG_H);
    }

    // Book title (14 regular, 2 lines)
    const auto& rBook = (*books)[static_cast<size_t>(bookIdx)];
    const auto titleLines =
        renderer.wrappedText(NOTOSANS_14_FONT_ID, rBook.title.c_str(), layout::RECENT_W, 2, EpdFontFamily::REGULAR);
    if (!titleLines.empty()) {
      renderer.drawText(NOTOSANS_14_FONT_ID, x, layout::RECENT_TITLE_LINE1, titleLines[0].c_str(), true,
                        EpdFontFamily::REGULAR);
    }
    if (titleLines.size() > 1) {
      renderer.drawText(NOTOSANS_14_FONT_ID, x, layout::RECENT_TITLE_LINE2, titleLines[1].c_str(), true,
                        EpdFontFamily::REGULAR);
    }
  }
}

void BalancedHomeUi::drawBottomPanel() {
  if (books == nullptr) return;

  struct PanelItem {
    const uint8_t* icon;
    const char* label;
  };

  std::array<PanelItem, 5> items{};
  int itemCount = 0;
  items[itemCount++] = {FolderIcon, tr(STR_BROWSE_FILES)};
  items[itemCount++] = {LibraryIcon, tr(STR_LIBRARY)};
  if (slotTab != CoverGridHomeUi::SlotTab::NONE) {
    items[itemCount++] = {BlocksIcon,
                          slotTab == CoverGridHomeUi::SlotTab::PLUGINS ? tr(STR_PLUGINS) : tr(STR_OPDS_BROWSER)};
  }
  items[itemCount++] = {TransferIcon, tr(STR_FILE_TRANSFER)};
  items[itemCount++] = {Settings2Icon, tr(STR_SETTINGS_TITLE)};

  const int screenW = renderer.getScreenWidth();
  const int screenH = renderer.getScreenHeight();
  const int cellW = screenW / itemCount;
  const int selectorBase = static_cast<int>(books->size());

  renderer.drawRect(0, layout::PANEL_LINE_Y, screenW, 1);

  for (int i = 0; i < itemCount; ++i) {
    const int cellX = i * cellW;
    const bool isSelected = (selected == selectorBase + i);

    if (isSelected) {
      renderer.fillRect(cellX, layout::PANEL_TOP, cellW, screenH - layout::PANEL_TOP);
    }

    if (!isSelected && items[i].icon != nullptr) {
      const int iconX = cellX + (cellW - layout::PANEL_ICON_SIZE) / 2;
      renderer.drawIcon(items[i].icon, iconX, layout::PANEL_ICON_Y, layout::PANEL_ICON_SIZE);
    }

    const int labelW = renderer.getTextWidth(NOTOSANS_14_FONT_ID, items[i].label);
    const int labelX = cellX + (cellW - labelW) / 2;
    renderer.drawText(NOTOSANS_14_FONT_ID, labelX, layout::PANEL_LABEL_BASE, items[i].label,
                      !isSelected, EpdFontFamily::REGULAR);
  }
}

void BalancedHomeUi::render() {
  // clearScreen() is called by HomeActivity before render(); do not call it here.
  coverCache.prepare();
  drawStatusBar();

  if (books == nullptr || books->empty()) {
    drawAddBooksCard();  // State 1: no books
  } else if (!hasContinueReading_) {
    drawStartReadingCard();  // State 2: books exist, no reading history (C-1)
    drawRecentSection();     // "Новые книги" with library books (C-2)
  } else {
    drawHeroSlot();     // State 3: current book in hero slot
    drawRecentSection(); // "Недавние"
  }

  drawBottomPanel();  // Always drawn (F-1)
}
