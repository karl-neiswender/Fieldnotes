# Fieldnotes icons (approved 2026-11-04)

Open `Icon-sheet.png` to compare the icons with Forever Goal Tracker references at 64 px and 18 px. Karl approved the first eight shapes, then approved the curved Share arrow and warning triangle. He approved the revised Cloth stack on 2026-11-04 and the Treasure chest on 2026-11-05. The open Book icon is a new proposal made from the existing plain closed Book.

The full-size transparent PNGs are the painted sources. `build-preview.ps1` clears faint stray alpha, sizes each icon to a transparent 64 x 64 canvas, and rebuilds the review sheet. The resulting `*-64.png` files were exported as uncompressed 32-bit TGA in `Media/icons`, with the names expected by `Style.Icon` (`statistics` becomes `stats-white`).

Image generation prompt used for each subject: match Forever Goal Tracker's hand-painted silver relief, thick sculpted bevel, bright upper-left highlights, charcoal recesses, dark contact shadow, and compact 18 px readability. The existing gear, note, pin, and plus icons were style references. The final Share follows the supplied curved right-pointing arrow reference; Warning follows the supplied triangle with a recessed exclamation mark. Book uses the supplied blank closed-book silhouette: plain cover, left spine, and visible pages at the lower and right edges. The open Book is an edit of that same icon: thin paper curving into one central gutter, layered page edges, and a turned upper-right corner over a thin dark cover. Treasure is a closed arched chest with a central keyhole, few broad seams, and the same silver facets. Built-in image generation produced the painted sources.

All five profession icons are assigned in `MapUI.lua`. The playback and Statistics icons replace their former placeholder textures. Share, Warning, Book, open Book, and Treasure are exported as assets; the current UI does not have separate icon slots for them. The open Book has not yet been approved.

Coin (2026-11-10): `coin.png` (Codex's single tilted coin in the set's chiseled silver relief, first named `coin-single-proposal.png`) is the Money icon, exported as `Media/icons/money-white.tga`. It replaced a placeholder coin stack. Note: rerunning `build-preview.ps1` re-renders every `*-64.png` slightly differently; restore the others from git if only one icon is meant to change.

