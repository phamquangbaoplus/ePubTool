<p align="center">
  <img src="ePubTool/Assets.xcassets/AppIcon.appiconset/icon_256x256@1x.png" width="128" height="128" alt="ePubTool logo">
</p>

<h1 align="center">ePubTool</h1>

<p align="center">An open-source macOS toolbox for EPUB workflows around Apple Books.</p>

<p align="center">
  <a href="LICENSE">MIT License</a> · Swift · SwiftUI · macOS
</p>

ePubTool brings small, focused book utilities into one native Mac app. It helps you work with your Apple Books library, export books as portable files, and prepare separate EPUB copies for editing. The sidebar keeps these utilities together and provides room for more tools as the project grows.

## Apple Books workflows

The current tool, **Manage Apple Books**, lets you:

- Load your Apple Books catalog and search by title, author, or filename.
- Export individual books or a selection of books to a folder you choose.
- Automatically repack unpacked EPUB folders into `.epub` archives during export—no separate repack step is needed.
- Copy already packaged EPUBs and PDFs to the export folder.
- Open separate EPUB copies in Calibre’s editor, individually or in batches.
- Reveal original books, edited copies, and exports in Finder.
- Follow progress and inspect or copy detailed console logs.
- Double-click a title or author to copy it.

## How export works

Apple Books can store an EPUB as an unpacked directory rather than a single archive. ePubTool packages those directories back into EPUB files, placing the uncompressed `mimetype` entry first, checking the package references, and testing the resulting ZIP archive. Apple-specific metadata and common filesystem clutter are excluded from the exported package.

The library database is opened read-only, and export works from the Apple Books original without modifying it. When a book needs to be downloaded from iCloud, the app requests the download and waits for it before exporting.

**Existing files with the same export filename are overwritten.** Duplicate output names within one export batch are reported as errors.

## Getting started

1. Open Apple Books and make sure your library is available on this Mac.
2. Launch ePubTool and select **Manage Apple Books** in the sidebar. The catalog loads automatically; use **Refresh** to reload it.
3. Search for books and select the ones you want.
4. Click **Export Selected**, or use a book’s export button, then choose the destination folder.
5. Use **Show Exports** to open the output folder.

If the library cannot be read, grant ePubTool **Full Disk Access** in **System Settings → Privacy & Security**, relaunch it, and refresh. The console includes details about access or library errors.

### Editing with Calibre

Editing requires Calibre installed at `/Applications/calibre.app`, including its `ebook-edit` executable. Calibre is an optional external application and is not bundled with ePubTool.

Choose **Edit** or **Edit Selected** to prepare separate EPUB copies and open them in Calibre. PDFs are skipped when editing a selection. Use **Show Edited Copy in Finder** to locate the working file.

Edits are saved to the separate copy; they are not written back to Apple Books. **Export always reads the Apple Books original**, not the edited copy. Import an edited file into Apple Books manually if you want to use it there.

## Build from source

1. Clone or download this repository.
2. Open `ePubTool.xcodeproj` in Xcode.
3. Select the **ePubTool** scheme and **My Mac** destination.
4. Choose your own signing team under **Signing & Capabilities** if required.
5. Build and run with **⌘R**.

Use an Xcode installation and macOS version compatible with the project’s configured SDK and deployment target. The app is written in Swift and SwiftUI and uses the system ZIP utility for repacking.

## Scope and limitations

- ePubTool focuses on file workflows around Apple Books; it is not an ebook reader.
- Repacking does not remove DRM or decrypt protected content.
- Apple Books library discovery depends on its local database structure and storage locations, which may change with macOS updates.
- iCloud-only content requires a working connection and an available download.
- More small tools can be added through the existing sidebar structure. Currently, **Manage Apple Books** is the available tool.

## Contributing

Bug reports, workflow suggestions, and pull requests are welcome. For bug reports, include your macOS and Xcode versions, steps to reproduce, and relevant console output. Remove private book titles and filesystem paths before sharing logs.

Keep changes focused on a specific tool or workflow, and build the project in Xcode before submitting a pull request.

## License

Released under the [MIT License](LICENSE). You may use, modify, and redistribute the software, including commercially, while retaining the copyright and license notice. See the license for its full terms.

This is an independent project, not affiliated with or endorsed by Apple. Apple Books is a trademark of Apple Inc.
