import 'dart:typed_data';

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/labels.dart';
import '../l10n/l10n.dart';
import 'sample_info.dart';

/// One printed label: the code plus a second line of context.
class LabelSpec {
  const LabelSpec(this.label, this.subtitle);

  final PlateLabel label;
  final String subtitle;
}

/// One label per planned plate of [info] (drop plates: one per plate too).
List<LabelSpec> labelsForSample(SampleInfo info, {int copies = 1}) {
  final subtitle = [
    if (info.experiment.isNotEmpty) info.experiment,
    if (info.condition.isNotEmpty) info.condition,
    if (info.timeH != null)
      '${info.timeH! % 1 == 0 ? info.timeH!.toInt() : info.timeH} h',
  ].join(' · ');
  return [
    for (final slot in info.slots)
      for (var i = 0; i < copies; i++)
        LabelSpec(
          PlateLabel(
            info.sampleId,
            dilutionExp: slot.dilutionExp,
            replicate: slot.replicate,
          ),
          subtitle,
        ),
  ];
}

const _cols = 3, _rows = 8, _perPage = _cols * _rows;
const _labelW = 70 * PdfPageFormat.mm, _labelH = 37 * PdfPageFormat.mm;

/// Where label [i] (0-based, row by row) of a sheet sits on the A4 page, in
/// PDF points from the top-left corner. The 210 × 296 mm grid fills the
/// page's width and is centred on its 297 mm height.
({double left, double top, double width, double height}) labelSlot(int i) {
  const top = (297 - _rows * 37) / 2 * PdfPageFormat.mm;
  return (
    left: i % _cols * _labelW,
    top: top + i ~/ _cols * _labelH,
    width: _labelW,
    height: _labelH,
  );
}

const _superscripts = {
  '-': '⁻',
  '0': '⁰',
  '1': '¹',
  '2': '²',
  '3': '³',
  '4': '⁴',
  '5': '⁵',
  '6': '⁶',
  '7': '⁷',
  '8': '⁸',
  '9': '⁹',
};

/// A4 sheet of 70 × 37 mm labels (3 × 8, the common 24-up layout), each with
/// a QR code and the sample, dilution and replicate in text. [fontData] is a
/// TrueType font for the text (the app passes its bundled Roboto);
/// [symbolFontData] has the superscripts Roboto lacks for "10⁻⁴" (the app
/// passes ColonySymbols).
Future<Uint8List> buildLabelSheet(
  List<LabelSpec> labels, {
  ByteData? fontData,
  ByteData? boldFontData,
  ByteData? thaiFontData,
  ByteData? thaiBoldFontData,
  ByteData? symbolFontData,
}) async {
  final font = fontData == null ? pw.Font.helvetica() : pw.Font.ttf(fontData);
  final bold = boldFontData == null
      ? pw.Font.helveticaBold()
      : pw.Font.ttf(boldFontData);
  final symbols = symbolFontData == null ? null : pw.Font.ttf(symbolFontData);
  // Thai sample IDs and experiment names fall back to a Thai font.
  final fallback = [if (thaiFontData != null) pw.Font.ttf(thaiFontData)];
  final boldFallback = [
    if (thaiBoldFontData != null) pw.Font.ttf(thaiBoldFontData),
    ?symbols,
  ];
  final doc = pw.Document(
    title: 'Colony Counter plate labels',
    creator: 'Colony Counter',
  );

  for (var start = 0; start < labels.length; start += _perPage) {
    final page = labels.sublist(
      start,
      (start + _perPage).clamp(0, labels.length),
    );
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        // Placed by position, not wrapped: 3 × 70 mm is the page's whole
        // width, and rounding would push the third label to the next row.
        build: (_) => pw.Stack(
          children: [
            for (final (i, spec) in page.indexed)
              pw.Positioned(
                left: labelSlot(i).left,
                top: labelSlot(i).top,
                child: pw.Container(
                  width: _labelW,
                  height: _labelH,
                  padding: const pw.EdgeInsets.all(3 * PdfPageFormat.mm),
                  child: pw.Row(
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: spec.label.encode(),
                        width: 29 * PdfPageFormat.mm,
                        height: 29 * PdfPageFormat.mm,
                      ),
                      pw.SizedBox(width: 3 * PdfPageFormat.mm),
                      pw.Expanded(
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _sampleIdText(
                              spec.label.sampleId,
                              pw.TextStyle(
                                font: bold,
                                fontSize: 11,
                                fontFallback: boldFallback,
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.RichText(
                              text: pw.TextSpan(
                                style: pw.TextStyle(
                                  font: bold,
                                  fontSize: 13,
                                  fontFallback: boldFallback,
                                ),
                                children: _codeLine(
                                  spec.label,
                                  superscripts: symbols != null,
                                ),
                              ),
                            ),
                            if (spec.subtitle.isNotEmpty) ...[
                              pw.SizedBox(height: 2),
                              pw.Text(
                                spec.subtitle,
                                style: pw.TextStyle(
                                  font: font,
                                  fontSize: 7,
                                  fontFallback: fallback,
                                ),
                                maxLines: 3,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

/// Smallest size (pt) a sample ID shrinks to before it is shortened.
const _minIdSize = 7.0;

/// [id] in at most two lines: at [style]'s size if it fits, else at the
/// largest size down to [_minIdSize] that does; an ID too long even then
/// loses its middle ("Lake-A-2026…-0042"), so IDs that differ only at the
/// end still print apart.
pw.Widget _sampleIdText(String id, pw.TextStyle style) => pw.LayoutBuilder(
  builder: (context, constraints) {
    pw.Text text(String s, double size, [int? maxLines]) => pw.Text(
      s,
      style: style.copyWith(fontSize: size),
      maxLines: maxLines,
    );
    // Whole when two lines are as tall as all of it.
    bool fits(String s, double size) {
      double height(int? maxLines) {
        final t = text(s, size, maxLines)
          ..layout(context, pw.BoxConstraints(maxWidth: constraints!.maxWidth));
        return t.box!.height;
      }

      return height(null) <= height(2) + 0.01;
    }

    for (var size = style.fontSize!; size >= _minIdSize; size -= 0.5) {
      if (fits(id, size)) return text(id, size, 2);
    }
    // The most characters kept around "…", a little more of the end.
    final chars = id.characters.toList();
    String cut(int keep) {
      final tail = (keep + 1) ~/ 2;
      return '${chars.take(keep - tail).join()}…'
          '${chars.skip(chars.length - tail).join()}';
    }

    var lo = 0, hi = chars.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (fits(cut(mid), _minIdSize)) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return text(cut(lo), _minIdSize, 2);
  },
);

/// "10⁻⁴  R2" as spans: superscript glyphs when the PDF has a font for them,
/// otherwise a smaller "-4" raised above the line.
List<pw.InlineSpan> _codeLine(PlateLabel label, {required bool superscripts}) {
  final exp = label.dilutionExp;
  return [
    if (exp == 0)
      pw.TextSpan(text: tr.neat)
    else if (exp != null) ...[
      const pw.TextSpan(text: '10'),
      superscripts
          ? pw.TextSpan(
              text: '-$exp'.split('').map((c) => _superscripts[c]).join(),
            )
          : pw.TextSpan(
              text: '-$exp',
              style: const pw.TextStyle(fontSize: 8),
              baseline: 5,
            ),
    ],
    if (label.replicate != null)
      pw.TextSpan(text: '${exp != null ? '  ' : ''}R${label.replicate}'),
  ];
}
