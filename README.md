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

## Install a release

Requires **Apple Silicon and macOS 27 or later**.

1. Download the app DMG from [GitHub Releases](https://github.com/phamquangbaoplus/ePubTool/releases/latest).
2. Open the DMG and drag **ePubTool.app** onto the **Applications** shortcut (`/Applications/ePubTool.app`). Wait for the copy to finish. The DMG includes **READ ME FIRST.txt** with the Terminal command and Full Disk Access instructions.
3. Open **Terminal**, paste this command, and press Return:

```bash
xattr -dr com.apple.quarantine "/Applications/ePubTool.app" && open "/Applications/ePubTool.app"
```

Only run this for a copy downloaded from this repository that you trust. The command removes the download quarantine attribute from **ePubTool only**, then opens it. It does not notarize the app or disable Gatekeeper system-wide. Release builds are currently ad-hoc signed and have not been notarized by Apple.

After this setup, open ePubTool normally from Applications. You may need to repeat the command after replacing it with a newly downloaded version.

If Terminal reports **No such file**, check that the app is named `ePubTool.app` and is inside `/Applications`. If access is denied or macOS still blocks opening, try opening the app once, then use **System Settings → Privacy & Security → Open Anyway** for ePubTool, if available. See [Apple’s instructions for opening downloaded apps](https://support.apple.com/102445). This command does not resolve incompatible macOS versions, damaged downloads, or organization-managed restrictions.

### Required: Full Disk Access

To read the Apple Books library, grant **ePubTool** Full Disk Access:

1. Open **System Settings → Privacy & Security → Full Disk Access**.
2. Click **+**, select **/Applications/ePubTool.app**, and authenticate if prompted.
3. Enable the switch beside **ePubTool**.
4. Quit the app completely with **⌘Q**, then reopen it from **Applications**.
5. Select **Manage Apple Books** and click **Refresh**.

The Terminal command above does **not** grant this permission; you must approve it in System Settings. If library access stops working after an update, remove the old entry and add the installed app again.

Eject the DMG after installation. Always launch the installed copy from Applications.

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

## Automatic releases

Every push to `main` runs [the release workflow](.github/workflows/release.yml). It builds the app, checks its signature and icon, packages a DMG with an Applications shortcut, installation instructions, and a SHA-256 checksum, and publishes a GitHub Release with generated release notes. No manual tag or version edit is required.

Versions use `1.0.<GitHub run number>`; failed runs may leave gaps. Re-running a workflow keeps the same version and does not replace an already published release. You can also start the workflow manually from the Actions tab on `main`. Rapid pushes may replace a pending run; the newest pending commit will be built.

Download builds from [Releases](https://github.com/phamquangbaoplus/ePubTool/releases/latest). Automated binaries currently require **Apple Silicon and macOS 27 or later**. They are ad-hoc signed, not Developer ID signed or notarized; macOS Gatekeeper may block them.

The workflow uses GitHub's built-in `GITHUB_TOKEN` with `contents: write`; no personal access token or Apple certificate is required for this release mode. GitHub Actions must be enabled for the repository, and repository rules must permit the workflow to create release tags. Developer ID signing and notarization require a separate Apple credential setup.

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
