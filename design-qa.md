**Comparison Target**

- Source visual truth: `/tmp/turbo-composer.png`
- Implementation screenshot: `/tmp/turbo-editor-header-controls.png`
- Quick-capture screenshot: `/tmp/turbo-composer-header-controls.png`
- Side-by-side focused comparison: `/tmp/task-editor-qa-comparison.png`
- Viewport: macOS desktop, 1512 × 982 points at 2× capture scale
- State: dark mode, existing One-Off task, no prerequisites

**Findings**

- No actionable P0, P1, or P2 findings remain.
- Typography: the editor matches quick capture's system type scale, title weight, muted placeholder treatment, and compact control labels.
- Spacing and layout: the former 820 × 620 minimum-size sheet and large unused canvas were removed. The editor now sizes to its content at 760 points wide, with dependencies immediately below the metadata rail and the footer attached to the content.
- Colors and tokens: all surfaces, borders, text, and semantic status colors use the existing `TurboTheme` tokens.
- Image and asset fidelity: the surface has no raster assets. All icons are SF Symbols; no placeholder artwork or custom-drawn assets are used.
- Copy and content: existing Turbo vocabulary is preserved. Dependencies are expressed as “Starts after” prerequisites, matching current task behavior.
- Interaction: title, notes, status, Now, field, project/operation, work mode, cadence, tools, dates, archive, dependency add/remove, Cancel, and Save remain functional.

**Focused Comparison Evidence**

- The body comparison shows the same title/notes hierarchy, capsule metadata controls, borders, and footer structure as quick capture.
- The editor adds only one primary block: a compact dependency section that expands with linked tasks.
- A separate detail crop was unnecessary because the controls are legible in the focused side-by-side comparison.

**Patches Made Since Previous QA Pass**

- Replaced the generic grouped form with the quick-capture editing structure.
- Removed minimum-size overrides from every task-editor sheet presentation.
- Reduced the editor to an intrinsic 760-point-wide sheet.
- Removed automatic title selection on open.
- Moved dependencies into a concise inline block with visible add/remove actions.
- Replaced editor breadcrumbs with Field and Project / Operation header controls.
- Added the same progressive placement controls to quick capture; Project / Operation stays hidden until a field is selected.
- Preserved and made task notes editable instead of clearing them on save.
- Disabled the unwanted focus ring on the header Now control.

**Implementation Checklist**

- [x] Debug build succeeds.
- [x] All four existing tests pass.
- [x] Existing-task editor opens inside the current app window as a sheet.
- [x] Empty dependency state is compact.
- [x] Linked dependency rows support removal and the add menu filters cycles and duplicates.
- [x] Quick-capture visual language is preserved.

**Follow-up Polish**

- P3: a task with several real prerequisites was not available in the captured workspace state; the multi-row dependency list was verified from code and constrained to a 126-point scrolling region.

final result: passed
