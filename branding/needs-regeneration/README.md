# Assets that still show the previous name or the wrong disk marks

These files were removed from the website and the README because a person can still read the previous product name (“Clean My Mac”), Portuguese UI, or disk marks at 90% and 95% inside the pixels. The app does not warn at 90% disk or clean at 95% disk. Recapture them before Product Hunt. Do not put the old files back under `docs/`.

| File | What is wrong |
|---|---|
| `og-card.png` | Previous name in the nav, headline, and menu mock. Portuguese. |
| `readme-storage-control.png` | Previous name in the window title. The gauge is at 95% while the scale’s real ceiling mark is 80%. |
| `app-popover-current.png` | Previous name in the menu title. Threshold labels 75/78 are right; the name is not. |
| `app-popover.webp` | Previous name, and the labels say alert at 90% and clean at 95%. |
| `video-poster.webp` | Same as the webp popover, plus the caption “90% warning · 95% optional cleanup”. |
| `clean-my-mac-demo.mp4` | 12 seconds. Same poster content for the whole clip: previous name and 90/95 disk copy. |

`docs/img/app-icon.png`, `docs/img/app-icon.svg`, and `docs/img/storage-hero.webp` do not contain that name. A new social card is generated at `docs/img/og-card.png`.

## Screenshots to capture on the Mac

This environment cannot run the SwiftUI menu-bar app. After the English build is open, capture:

1. Menu bar popover under 75%: status “Storage looks healthy”, disk gauge, memory gauge, Automatic cleanup, Open at login, Check now, Clean now, Deep Clean, Emergency Clean.
2. The same popover at 75–77%: status “Storage needs attention”.
3. The same popover at 78% or above: status “Cleanup needed”. If you can reach a real shortfall above 80%, also capture “80% ceiling not protected”.
4. The confirmation that replaces the buttons for Safe, then Deep, then Emergency.
5. Settings: Memory relief, Chrome, cleanup level, and the three destinations. Include the external-drive section if a volume is available.
6. A new 12-second recording of a real cleanup. The menu title must read “AI, Leave My Mac Alone!”. Visible disk marks must be 75%, 78%, and 80%, not 90% or 95%.

The website screenshots in `docs/img/launch/` are the English site only. They are not substitutes for the menu-bar captures above.
