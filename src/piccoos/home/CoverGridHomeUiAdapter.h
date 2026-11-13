#pragma once

#include "components/CoverGridHomeUi.h"
#include "components/UITheme.h"
#include "piccoos/home/HomeScreenUi.h"

// PiccoOS: D-033. Thin adapter: makes upstream CoverGridHomeUi implement
// HomeScreenUi. No new logic; all calls forward to the wrapped instance.
// CoverGridHomeUi (final) is unchanged per D-017.
class CoverGridHomeUiAdapter final : public HomeScreenUi {
 public:
  explicit CoverGridHomeUiAdapter(GfxRenderer& renderer) : inner(renderer) {}
  void begin(const std::vector<RecentBook>& books, CoverGridHomeUi::SlotTab slotTab,
             bool hasContinueReading) override {
    inner.begin(books, slotTab, hasContinueReading);
  }
  void refreshCoverPaths() override { inner.refreshCoverPaths(); }
  void setSelection(int selection) override { inner.setSelection(selection); }
  int selectedAction(const MappedInputManager& input) override { return inner.selectedAction(input); }
  // CoverGridHomeUi uses one height for all slots; index is ignored here.
  int thumbHeightFor(int /*index*/) const override { return inner.thumbHeightFor(); }
  bool takeThumbHeightChanged() override { return inner.takeThumbHeightChanged(); }
  int maxBooks() const override { return CoverGridHomeUi::MAX_BOOKS; }
  void render() override { UITheme::drawCoverGridHome(inner); }

 private:
  CoverGridHomeUi inner;
};
