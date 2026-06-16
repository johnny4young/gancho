import { execFile } from "node:child_process";
import * as path from "node:path";
import * as vscode from "vscode";

/// Where to send a developer who doesn't have Gancho yet — the funnel.
const DOWNLOAD_URL = "https://getgancho.app";

export function activate(context: vscode.ExtensionContext): void {
  context.subscriptions.push(
    vscode.commands.registerCommand("gancho.saveSelection", saveSelection),
  );
}

export function deactivate(): void {
  // Nothing to tear down: each save spawns a short-lived CLI process.
}

/// Takes the current selection (or the whole document if nothing is selected)
/// plus its language id, and hands it to `gancho save`. Everything stays
/// local — the CLI writes straight to the on-device store.
async function saveSelection(): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor) {
    void vscode.window.showWarningMessage("Gancho: open a file and select text to save.");
    return;
  }

  const { selection, document } = editor;
  const text = selection.isEmpty ? document.getText() : document.getText(selection);
  if (text.trim().length === 0) {
    void vscode.window.showWarningMessage("Gancho: nothing to save (the selection is empty).");
    return;
  }

  const language = document.languageId;
  const title = document.isUntitled ? "Snippet" : path.basename(document.fileName);
  const encoded = Buffer.from(text, "utf8").toString("base64");
  const cliPath = vscode.workspace.getConfiguration("gancho").get<string>("path", "gancho");

  try {
    await runGancho(cliPath, [
      "save",
      "--title",
      title,
      "--language",
      language,
      "--content-base64",
      encoded,
    ]);
    void vscode.window.showInformationMessage(`Saved “${title}” to your Gancho Library.`);
  } catch (error) {
    handleError(error);
  }
}

/// Runs the CLI with an args array (no shell → no injection from file paths
/// or selection contents).
function runGancho(cliPath: string, args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    execFile(cliPath, args, (error) => (error ? reject(error) : resolve()));
  });
}

function handleError(error: unknown): void {
  const code = (error as NodeJS.ErrnoException | undefined)?.code;
  if (code === "ENOENT") {
    // The CLI isn't on PATH → Gancho isn't installed. Offer the download.
    void vscode.window
      .showErrorMessage(
        "Gancho isn't installed. Install it to save snippets from your editor.",
        "Download Gancho",
      )
      .then((choice) => {
        if (choice === "Download Gancho") {
          void vscode.env.openExternal(vscode.Uri.parse(DOWNLOAD_URL));
        }
      });
    return;
  }
  const message = error instanceof Error ? error.message : String(error);
  void vscode.window.showErrorMessage(`Gancho save failed: ${message}`);
}
