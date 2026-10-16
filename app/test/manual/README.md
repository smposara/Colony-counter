# User manual screenshots

The picture manual in `docs/manual/` is made from real app screens. Each
chapter is a widget test that drives the app like a user, in English and Thai,
and saves a screenshot per step with the controls to point at.

    bash test/manual/make_manual.sh      # all chapters → docs/manual/

## Files

- `harness.dart`: `chapter()`, `Manual` (start, tap, shot, ...), fonts, a fake
  camera and photo picker (`nextPhoto = fixture('medium.jpg')`).
- `<chapter>_manual.dart`: one chapter. Not named `_test.dart`, so the normal
  test run (`flutter test`) skips them.
- `annotate.py`: draws a numbered red-pink outline on each marked control.
- `docs/manual/text/<chapter>.json`: the chapter's titles and captions (en, th).
- `build_manual.py`: builds `docs/manual/index.html` from the text and images.

## Writing a chapter

```dart
chapter('count', (m) async {
  await m.start(seed: (store) async { /* optional data */ });
  await m.shot('1-home', [(find.text(tr.homeCountPlate), Mark.tap)]);
  nextPhoto = fixture('medium.jpg');          // what the camera returns
  await m.tap(find.text(tr.homeCountPlate));
  await m.shot('2-review', [(find.text(tr.reviewModeEdit), Mark.tap)]);
});
```

- Find widgets by the app's own strings (`tr.xxx` from `l10n/l10n.dart`), so
  the same code works in both languages. Tooltips: `find.byTooltip(tr.xxx)`.
- A mark on a label or icon outlines its whole button. `Mark.look` outlines
  exactly the finder (a result, a chart): use it for "see here".
- Marks are numbered 1, 2, 3 in the order given; each gets one caption.
- One shot = one screen state. 1–3 marks per shot; split busier steps.
- Shot names: `<step number>-<slug>`, saved as `<chapter>-<name>.<lang>.png`.

## Caption file (`docs/manual/text/<chapter>.json`)

```json
{
  "id": "count",
  "order": 2,
  "icon": "camera",
  "title": {"en": "Count a plate", "th": "นับเพลต"},
  "summary": {"en": "Photo, check, save.", "th": "ถ่ายภาพ ตรวจ บันทึก"},
  "sections": [
    {
      "title": {"en": "Take the photo", "th": "ถ่ายภาพ"},
      "steps": [
        {
          "shot": "count-1-home",
          "marks": [{"en": "Tap Count plate", "th": "แตะ นับเพลต"}],
          "tip": {"en": "Lid off, plate in the lightbox.", "th": "..."}
        }
      ]
    }
  ]
}
```

Words are short: a caption per mark (an action, under 8 words), an optional
one-line tip. Use the app's own button names in quotes-free form, exactly as
they appear on screen in each language.
