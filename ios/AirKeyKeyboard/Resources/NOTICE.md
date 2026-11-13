# Keyboard resources

`en.glyd` is the typing engine's English dictionary, a compiled binary of:

- The English word list from the Android Open Source Project,
  `platform/packages/inputmethods/LatinIME`, `dictionaries/`
  (https://android.googlesource.com/platform/packages/inputmethods/LatinIME/+/refs/heads/main/dictionaries/).
  Copyright The Android Open Source Project, licensed under the Apache License,
  Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0). The words,
  frequencies and flags are unchanged; only the format is.
- Word-pair and word-triple counts from the English sentences of Tatoeba
  (https://tatoeba.org), licensed under Creative Commons Attribution 2.0
  France (CC BY 2.0 FR, https://creativecommons.org/licenses/by/2.0/fr/).
  Only the counts are kept, never the sentences.
- A supplement of everyday texting words, names, apps and places.

`packs.json` holds optional vocabulary packs (Hinglish and others).

`Fonts/` are the keyboard themes' typefaces, each under the SIL Open Font
License 1.1; each font's licence is beside it (`*-OFL.txt`).
