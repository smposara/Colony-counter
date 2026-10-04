import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/labels.dart';
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

/// A4 sheet of 70 × 37 mm labels (3 × 8, the common 24-up layout), each with
/// a QR code and the sample, dilution and replicate in text. [fontData] is a
/// TrueType font for the text (the app passes its bundled Roboto).
Future<Uint8List> buildLabelSheet(
  List<LabelSpec> labels, {
  ByteData? fontData,
  ByteData? boldFontData,
  ByteData? thaiFontData,
  ByteData? thaiBoldFontData,
}) async {
  const cols = 3, rows = 8;
  const labelW = 70 * PdfPageFormat.mm, labelH = 37 * PdfPageFormat.mm;
  final font = fontData == null ? pw.Font.helvetica() : pw.Font.ttf(fontData);
  final bold = boldFontData == null
      ? pw.Font.helveticaBold()
      : pw.Font.ttf(boldFontData);
  // Thai sample IDs and experiment names fall back to a Thai font.
  final fallback = [if (thaiFontData != null) pw.Font.ttf(thaiFontData)];
  final boldFallback = [
    if (thaiBoldFontData != null) pw.Font.ttf(thaiBoldFontData),
  ];
  final doc = pw.Document(
    title: 'Colony Counter plate labels',
    creator: 'Colony Counter',
  );
  const perPage = cols * rows;
  for (var start = 0; start < labels.length; start += perPage) {
    final page = labels.sublist(
      start,
      (start + perPage).clamp(0, labels.length),
    );
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Padding(
          // Centre the 210 × 296 mm grid on the 210 × 297 mm page.
          padding: const pw.EdgeInsets.only(top: 0.5 * PdfPageFormat.mm),
          child: pw.Wrap(
            children: [
              for (final spec in page)
                pw.Container(
                  width: labelW,
                  height: labelH,
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
                            pw.Text(
                              spec.label.sampleId,
                              style: pw.TextStyle(
                                font: bold,
                                fontSize: 11,
                                fontFallback: boldFallback,
                              ),
                              maxLines: 2,
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              [
                                if (spec.label.dilutionExp != null)
                                  '10^-${spec.label.dilutionExp}',
                                if (spec.label.replicate != null)
                                  'R${spec.label.replicate}',
                              ].join('  '),
                              style: pw.TextStyle(
                                font: bold,
                                fontSize: 13,
                                fontFallback: boldFallback,
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
            ],
          ),
        ),
      ),
    );
  }
  return doc.save();
}
