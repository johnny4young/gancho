# Gancho: Save Selection — VS Code extension

Save the current editor selection to your **Gancho** clipboard Library as a
code snippet, with its language attached. Everything is local: the extension
shells out to the `gancho` CLI, which writes straight to the on-device store —
no account, no network, works offline.

## How it works

1. Select code (or nothing, to save the whole file).
2. Run **“Gancho: Save Selection”** from the Command Palette.
3. The selection + the document's `languageId` are base64-encoded and passed to
   `gancho save --title <file> --language <id> --content-base64 <…>`.
4. The snippet appears in the Gancho Library, searchable, with its language.

If `gancho` isn't on your `PATH`, the extension offers a **Download Gancho**
link instead of failing silently.

## Requirements

- The `gancho` CLI (installed with the app, or `brew install gancho`).
- Point the extension at a non-default binary with the **`gancho.path`**
  setting if needed.

## Build from source

```bash
npm install
npm run compile        # emits out/extension.js
```

Press <kbd>F5</kbd> in VS Code to launch an Extension Development Host, or
package a `.vsix` with `npx @vscode/vsce package`.

## Publishing

Marketplace publishing is owner-gated: it needs a `vsce` publisher account and
`npx @vscode/vsce publish`. The `publisher` field in `package.json` is a
placeholder until then.
