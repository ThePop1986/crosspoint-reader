#pragma once

#include <vector>

#include "RecentBooksStore.h"
#include "components/CoverGridHomeUi.h"

class MappedInputManager;

// PiccoOS: abstract interface for Home screen UI implementations.
// CoverGridHomeUiAdapter wraps upstream CoverGridHomeUi (D-017).
// BalancedHomeUi implements Balanced 3.0 (D-033).
class HomeScreenUi {
 public:
  virtual ~HomeScreenUi() = default;
  virtual void begin(const std::vector<RecentBook>& books, CoverGridHomeUi::SlotTab slotTab,
                     bool hasContinueReading) = 0;
  virtual void refreshCoverPaths() = 0;
  virtual void setSelection(int selection) = 0;
  // Returns a flat selectorIndex to activate, or -1 for no Tap-level event.
  virtual int selectedAction(const MappedInputManager& input) = 0;
  // Thumb generation height for cover at position `index`
  // (index 0 = hero, index 1–3 = recents in BalancedHomeUi).
  virtual int thumbHeightFor(int index) const = 0;
  // PiccoOS: Balanced also uses flat nav (linearNavigation()=true, D-037).
  virtual bool linearNavigation() const { return false; }
  // PiccoOS: visible books entered in selectorIndex, Confirm, miniatures, and resize (R1, C-1).
  // Default = maxBooks(); BalancedHomeUi overrides to return visible_ (books actually shown).
  virtual int visibleBooks() const { return maxBooks(); }
  // PiccoOS: focus Transfer on empty book list (Balanced only); upstream CoverGrid unchanged (R5).
  virtual bool focusTransferWhenEmpty() const { return false; }
  // Returns true once after the thumb heights are first established; false thereafter.
  virtual bool takeThumbHeightChanged() = 0;
  virtual int maxBooks() const = 0;
  // Draw the complete Home screen into the renderer's framebuffer (no clearScreen).
  virtual void render() = 0;
};
