# OpenCanopy Resources

This directory must contain the OpenCanopy GUI assets for the boot picker to display graphically.

## How to populate

1. Download the latest **OcBinaryData** from:
   https://github.com/acidanthera/OcBinaryData

2. Copy the contents of the `Resources` folder from OcBinaryData into this directory, so you end up with:
   ```
   OC/Resources/
   ├── Audio/       (boot chime audio files)
   ├── Font/        (font files for the picker)
   ├── Image/       (icon set, e.g. Acidanthera\GoldenGate)
   └── Label/       (disk label files)
   ```

3. The `Image` subdirectory must contain an icon set matching your `PickerVariant` setting in `config.plist` (default is `Auto`, which maps to `Acidanthera\GoldenGate`).

Without these files, OpenCanopy falls back to the text-mode picker even though `PickerMode` is set to `External` in config.plist.
