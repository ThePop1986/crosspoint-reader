#pragma once

#include <array>
#include <string>
#include <vector>

#include "RecentBooksStore.h"
#include "components/HomeCoverCache.h"
#include "piccoos/home/HomeScreenUi.h"

class GfxRenderer;

// PiccoOS: Balanced 3.0 Home screen (D-033). Portrait 480×800 layout per spec.
class BalancedHomeUi final : public HomeScreenUi {
 public:
  static constexpr int MAX_BOOKS = 4;
  // D-029: two thumb heights
  static constexpr int HERO_HEIGHT = 300;
  static constexpr int HERO_WIDTH = 200;
  static constexpr int RECENT_HEIGHT = 192;
  static constexpr int RECENT_WIDTH = 128;

  explicit BalancedHomeUi(GfxRenderer& renderer);
  void begin(const std::vector<RecentBook>& books, CoverGridHomeUi::SlotTab slotTab,
             bool hasContinueReading) override;
  void refreshCoverPaths() override;
  void setSelection(int selection) override { selected = selection; }
  int selectedAction(const MappedInputManager& input) override;
  // C-1: hero height only when hasContinueReading_; all slots RECENT_HEIGHT otherwise.
  int thumbHeightFor(int index) const override {
    return (hasContinueReading_ && index == 0) ? HERO_HEIGHT : RECENT_HEIGHT;
  }
  bool linearNavigation() const override { return true; }
  int visibleBooks() const override { return visible_; }     // R1
  bool focusTransferWhenEmpty() const override { return true; }  // R5
  bool takeThumbHeightChanged() override;
  int maxBooks() const override { return MAX_BOOKS; }
  void render() override;

 private:
  void drawStatusBar();
  void drawHeroSlot();         // state 3: current book with thumb_300
  void drawStartReadingCard(); // state 2: no history, books exist (C-1)
  void drawAddBooksCard();     // state 1: no books at all
  void drawRecentSection();
  void drawBottomPanel();

  GfxRenderer& renderer;
  HomeCoverCache coverCache;
  const std::vector<RecentBook>* books = nullptr;
  CoverGridHomeUi::SlotTab slotTab = CoverGridHomeUi::SlotTab::NONE;
  bool hasContinueReading_ = false;
  bool showAllBooks_ = false;  // «Все книги ›» shown (computed before resize, R1)
  int visible_ = 0;            // visible book count after trimming (R1)
  std::array<std::string, MAX_BOOKS> coverPaths;
  std::array<int, MAX_BOOKS> bookProgress{};  // reading % per slot, -1 = unknown
  int selected = 0;
  bool thumbHeightChanged_ = true;
};
