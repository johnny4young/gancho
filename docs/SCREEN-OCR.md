# Copy text from the screen

Unreleased macOS feature, available on the Free tier. Automatic searchable-image
indexing remains a separate Pro feature. This action requires macOS 15.4 or later.

## Select and copy

1. Display the image or other region whose text you want to copy.
2. Press **Control–Option–T**, or choose **Copy text from screen** from Gancho's
   menu. Change the shortcut in **Settings → General** if it conflicts with
   another application.
3. On first use, read the purpose explanation and grant Screen Recording access
   in macOS when ready. Cancelling the explanation does not start capture.
4. Drag a rectangle using the hook-and-crosshair cursor. Its cross intersection
   is the selection point. Begin on either monitor; the rectangle is limited to
   the monitor where the drag starts. **Escape** cancels.
5. When recognition finishes, paste manually into the destination application.
   Gancho does not paste for you. The confirmation contains no recognized text.

Choose **Review** from the confirmation to select or edit the result and copy it
again. Only **Save as clip** stores the reviewed text. The confirmation and its
unopened result are short-lived; open Review promptly if you need to edit.

## Privacy and interruptions

- Recognition runs locally with the existing image-text engine. Capture is one
  in-memory region image, not a recording, and creates no temporary screenshot
  file or automatic clip. Manual extraction does not enable indexing or sync.
- Saving explicitly uses the normal classification, privacy, retention and
  configured sync rules for a new text clip.
- If you copy something else during recognition, Gancho preserves that newer
  clipboard content. Review and copy the OCR result explicitly instead.
- Starting another OCR request supersedes the previous one. Cancellation, an
  empty selection or an unreadable image must not erase the clipboard.
- Private Mode prevents this action and cancels pending selection or recognition.
  Turning it off does not resume an earlier request; invoke the action again.
  Recognized secrets stay masked in Review and are never copied automatically.
  Permission to capture the screen is
  independent of copying text from an image already saved in Gancho.

## If capture is unavailable

Use **Open Settings** in the permission guidance to check Screen Recording access,
then retry the action. If macOS asks you to reopen Gancho, do so before retrying.
For **No readable text found**, select a larger, sharper region containing text;
the previous clipboard content remains intact.

## Verification boundary

Unit tests cover coordinate conversion, clipping, authorization decisions,
request cancellation and clipboard conflicts. UI tests cover the selector,
purpose cancellation, review and permission-denied behavior with isolated data.
Those tests do not substitute for real OS permission changes, compositor/focus
behavior or Retina/non-Retina and multimonitor capture checks. Record those
separately before describing a build as fully validated.
