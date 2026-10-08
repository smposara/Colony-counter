import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/annotate.dart';
import '../core/background.dart';
import '../core/classical.dart';
import '../core/colour.dart';
import '../core/drop_layout.dart';
import '../core/drop_stats.dart';
import '../core/petrifilm.dart';
import '../core/pipeline.dart';
import '../core/plate.dart';
import '../core/spots.dart';
import '../data/drop_results.dart';
import '../data/plate_record.dart';
import '../data/plate_store.dart';
import '../data/sample_info.dart';
import '../l10n/l10n.dart';
import '../l10n/labels.dart';
import 'drop_table.dart';
import 'format.dart';
import 'insets.dart';
import 'photo_flow.dart';
import 'save_sheet.dart';
import 'timelapse_screen.dart';

const double kRimFraction = 0.95;

enum _Mode { zoom, edit, plate, spots, colour, gas, yellow, squares }

/// Default drop diameter for a 10 µL drop on agar.
const double kDropDiameterMm = 7;

/// Shows the automatic count over the photo and lets the user correct it.
///
/// Open with [photo] (encoded image bytes) for a new capture (it is counted on arrival) or with
/// [record] to revisit a saved plate.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.store,
    this.photo,
    this.record,
    this.guided = false,
    this.preset,
    this.laterPhotoOf,
    this.initialPlate,
  }) : assert(photo != null || record != null);

  final PlateStore store;
  final Uint8List? photo;
  final PlateRecord? record;
  final bool guided;

  /// Sample plan and plate slot this new photo belongs to, if any.
  final PlatePreset? preset;

  /// Time-lapse: [photo] is a later photo of this saved plate. Sample,
  /// dilution, plate type and so on are taken from it.
  final PlateRecord? laterPhotoOf;

  /// Where the plate is in [photo], when already known (several plates in
  /// one photo); otherwise it is searched for.
  final Plate? initialPlate;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _viewer = TransformationController();
  Uint8List? _photo;

  bool _busy = false;
  String? _error;
  _Mode _mode = _Mode.edit;

  /// Marks drawn over the photo; off for an unmarked look at the plate.
  bool _showMarks = true;

  int _imageW = 0, _imageH = 0;
  Plate? _plate;
  List<Colony> _colonies = [];
  int _autoCount = 0;
  List<String> _flags = [];
  double _kSigma = 4.0;
  final List<(List<Colony>, List<Spot>, List<Colony>, Set<(int, int)>)> _undo =
      [];
  bool _dirty = false;

  /// Drops of a drop plate (empty for whole plates).
  List<Spot> _spots = [];
  bool _drop = false;
  ColourMode _colourMode = ColourMode.none;
  int? _dragSpot;

  /// Dragging the agar in Drops mode moves every drop.
  bool _dragAllSpots = false;
  PlateFormat _format = PlateFormat.dish90;
  bool _spotsMoved = false;

  /// Automatic detections removed by the user (kept for training data).
  List<Colony> _rejected = [];

  /// Dry films: the printed grid found in the photo.
  FilmGrid? _filmGrid;

  /// Dry films: grid squares the user left out of the estimate.
  Set<(int, int)> _excluded = {};

  /// The grid is good enough to estimate from its squares.
  bool get _gridOk =>
      _filmGrid != null && _filmGrid!.strength >= kGridMinStrength;

  /// Some result is above the counting range, so squares can be chosen.
  bool get _filmAboveRange {
    if (!_film || _plate == null) return false;
    final max = kFilmTypes[_filmType]!.countMax;
    return _filmTally.counts.values.any((v) => v > max);
  }

  bool get _film => _format.isFilm;
  String get _filmType => _format.film!;

  /// Counts per result of a dry film, from the current marks.
  FilmTally get _filmTally => tallyFilm(
    _filmType,
    filmColoniesOf(_filmType, _colonies),
    _filmGrid,
    _plate!,
    excluded: _excluded,
  );

  /// Whether each mark counts towards any of the film's results.
  List<bool> get _filmCounted {
    final type = _filmType;
    final results = kFilmTypes[type]!.results;
    return [
      for (final c in filmColoniesOf(type, _colonies))
        results.any((k) => filmRule(type, k, c)),
    ];
  }

  /// Film modes: telling the two kinds apart, gas and yellow zones matter
  /// only for the types whose rules use them.
  bool get _filmKindMode =>
      _film && const {'ec', 'eb', 'ym'}.contains(_filmType);
  bool get _filmGasMode =>
      _film && const {'ec', 'cc', 'eb'}.contains(_filmType);
  bool get _filmYellowMode => _film && _filmType == 'eb';

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    if (r != null) {
      _loadSavedPhoto(r);
      _imageW = r.imageWidth;
      _imageH = r.imageHeight;
      _plate = r.plate;
      _colonies = List.of(r.colonies);
      _autoCount = r.autoCount;
      _flags = List.of(r.flags);
      _kSigma = r.kSigma;
      _spots = List.of(r.spots);
      _drop = r.isDropPlate;
      _colourMode = r.colourMode;
      _format = r.format;
      _rejected = List.of(r.rejected);
      _filmGrid = r.filmGrid;
      _excluded = r.excludedSquares.toSet();
    } else {
      final info = widget.preset?.info;
      final base = widget.laterPhotoOf;
      _drop = base?.isDropPlate ?? info?.isDrop ?? false;
      _colourMode = base?.colourMode ?? info?.colourMode ?? ColourMode.none;
      _format = base?.format ?? info?.format ?? widget.store.defaultFormat;
      if (_format.isFilm) {
        _drop = false;
        _colourMode = ColourMode.none;
      }
      if (base != null && base.isDropPlate) {
        // Same drops as before; their positions are adjusted after counting.
        _spots = List.of(base.spots);
      }
      _photo = widget.photo!;
      _recount(plate: widget.initialPlate);
    }
  }

  Future<void> _loadSavedPhoto(PlateRecord r) async {
    final bytes = await widget.store.readPhoto(r);
    if (!mounted) return;
    setState(() {
      _photo = bytes;
      if (bytes == null) _error = tr.reviewPhotoMissing;
    });
  }

  int get _count => _colonies.fold(0, (s, c) => s + c.n);
  int get _added => _colonies.where((c) => c.manual).length;
  int get _removed =>
      _autoCount - _colonies.where((c) => !c.manual).fold(0, (s, c) => s + c.n);
  bool get _hasEdits => _undo.isNotEmpty || _added > 0 || _removed != 0;

  Future<void> _recount({Plate? plate}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_film) {
        final res = await countFilmInBackground(
          FilmJob(_photo!, _filmType, area: plate),
        );
        if (!mounted) return;
        setState(() {
          _imageW = res.imageWidth;
          _imageH = res.imageHeight;
          _plate = res.plate;
          _filmGrid = res.grid;
          _excluded = {};
          _colonies = marksOf(_filmType, res.colonies);
          _autoCount = _colonies.fold(0, (s, c) => s + c.n);
          _flags = res.flags;
          _rejected = [];
          _spots = [];
          _drop = false;
          _undo.clear();
          _dirty = true;
        });
        return;
      }
      if (_drop && _spots.isEmpty && _dropTemplate is! FreeTemplate) {
        await _countWithLayout(plate);
        return;
      }
      final res = await countPhotoInBackground(
        _photo!,
        CountOptions(
          plate: plate,
          format: _format,
          rimFraction: kRimFraction,
          params: DetectParams(kSigma: _kSigma),
        ),
      );
      if (!mounted) return;
      setState(() {
        _imageW = res.imageWidth;
        _imageH = res.imageHeight;
        _plate = res.plate;
        _colonies = _classified(res.colonies, _colourMode);
        _autoCount = res.count;
        _flags = res.flags;
        _rejected = [];
        final base = widget.laterPhotoOf;
        if (base != null && widget.record == null && !_spotsMoved) {
          // Carry the earlier photo's drops over to where the plate is now.
          _spotsMoved = true;
          final k = res.plate.radius / base.plate.radius;
          _spots = [
            for (final sp in _spots)
              sp.copyWith(
                cx: res.plate.cx + (sp.cx - base.plate.cx) * k,
                cy: res.plate.cy + (sp.cy - base.plate.cy) * k,
                radius: sp.radius * k,
              ),
          ];
        }
        _undo.clear();
        _dirty = true;
        if (_drop && _spots.isEmpty) _spots = _suggestSpots();
      });
    } catch (e) {
      if (mounted) setState(() => _error = tr.reviewCouldNotCount('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDiscardEdits() async {
    if (!_hasEdits) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.reviewRecountTitle),
        content: Text(tr.reviewRecountBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr.reviewCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr.reviewRecount),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // --- drops and colours ----------------------------------------------------

  static List<Colony> _classified(List<Colony> colonies, ColourMode mode) {
    if (mode == ColourMode.none) {
      return [for (final c in colonies) c.withCls(0)];
    }
    final measured = [
      for (final c in colonies)
        if (c.colour != null) c.colour!,
    ];
    final cls = classifyColours(measured, mode);
    var k = 0;
    return [
      for (final c in colonies) c.colour == null ? c : c.withCls(cls[k++]),
    ];
  }

  double get _dropRadiusPx => kDropDiameterMm / 2 / (_plate?.mmPerPx ?? 0.05);

  /// Dilution and replicate for the [i]-th drop, from the sample plan.
  Spot _labelSpot(Spot s, int i) {
    final info = _dropPlan;
    if (info == null) {
      return s.copyWith(
        dilutionExp: widget.record?.dilutionExp ?? 0,
        replicate: i + 1,
      );
    }
    // Drops beyond the plan are flagged rather than wrapped round.
    final l = info.dropLabel(_dropSlot, i);
    return s.copyWith(
      dilutionExp: l.dilutionExp,
      replicate: l.replicate,
      flags: [...s.flags, if (l.unplanned) 'unplanned'],
    );
  }

  List<Spot> _suggestSpots() {
    final pl = _plate;
    if (pl == null) return [];
    final found = suggestSpots(
      _colonies,
      pl.mmPerPx,
      dropDiameterMm: kDropDiameterMm,
    );
    return [for (var i = 0; i < found.length; i++) _labelSpot(found[i], i)];
  }

  /// The sample's drop plan, when this plate belongs to one (from the plan
  /// being photographed, or the saved plate's sample).
  SampleInfo? get _dropPlan {
    final r = widget.record;
    final info =
        widget.preset?.info ??
        (r != null && widget.store.hasPlan(r.sampleId)
            ? widget.store.sampleInfo(r.sampleId)
            : null);
    return info != null && info.isDrop ? info : null;
  }

  /// Which plate of the plan this is.
  Slot get _dropSlot {
    final preset = widget.preset;
    if (preset != null) return preset.slot;
    final r = widget.record;
    final plan = _dropPlan;
    if (r == null || plan == null) return const Slot();
    return plan.dropLayout == DropLayout.replicates
        ? Slot(
            dilutionExp: r.spots.isEmpty
                ? r.dilutionExp
                : r.spots.first.dilutionExp,
          )
        : Slot(replicate: r.replicate);
  }

  DropTemplate get _dropTemplate =>
      _dropPlan?.dropTemplate ?? const FreeTemplate();

  /// Counts the plate by fitting the planned layout to it: every planned
  /// drop is found, empty and confluent ones included.
  Future<void> _countWithLayout(Plate? plate) async {
    final info = _dropPlan!;
    final slot = _dropSlot;
    final res = await countDropPlateInBackground((
      _photo!,
      _dropTemplate,
      info.dropDilutions(slot),
      info.dropVolumeUl,
      _format,
      plate,
    ));
    if (!mounted) return;
    final (colonies, spots) = res.toSpots();
    setState(() {
      _imageW = res.imageWidth;
      _imageH = res.imageHeight;
      _plate = res.plate;
      _colonies = _classified(colonies, _colourMode);
      _autoCount = _colonies.fold(0, (s, c) => s + c.n);
      _flags = [
        ...res.flags,
        if (_colonies.any((c) => c.n > 1)) 'clusters_estimated',
      ];
      _rejected = [];
      // All dilutions on one plate: the plate is the replicate.
      _spots = info.dropLayout == DropLayout.dilutions
          ? [for (final s in spots) s.copyWith(replicate: slot.replicate ?? 1)]
          : spots;
      _undo.clear();
      _dirty = true;
    });
  }

  /// Finds the drops again from the photo (the layout fit, or colony groups).
  Future<void> _findDropsAgain() async {
    if (!await _confirmDiscardEdits()) return;
    setState(() => _spots = []);
    await _recount(plate: _plate);
  }

  /// Ring layouts: moves every label one drop round, for when the first
  /// dilution was put somewhere else than the app chose.
  void _turnLabels() {
    final placed = [
      for (var i = 0; i < _spots.length; i++)
        if (_spots[i].position != null) i,
    ];
    if (placed.length < 2) return;
    final n = placed.length;
    final byPos = {for (final i in placed) _spots[i].position!: _spots[i]};
    final positions = byPos.keys.toList()..sort();
    setState(() {
      _push();
      final next = [..._spots];
      for (final i in placed) {
        final p = positions.indexOf(_spots[i].position!);
        final from = byPos[positions[(p - 1 + n) % n]]!;
        next[i] = _spots[i].copyWith(
          dilutionExp: from.dilutionExp,
          replicate: from.replicate,
          position: from.position,
        );
      }
      _spots = next;
    });
  }

  int? _hitSpot(Offset p) {
    int? best;
    for (var i = 0; i < _spots.length; i++) {
      if (_spots[i].contains(p.dx, p.dy) &&
          (best == null || _spots[i].radius < _spots[best].radius)) {
        best = i;
      }
    }
    return best;
  }

  void _setDrop(bool drop) {
    setState(() {
      _push();
      _drop = drop;
      if (drop && _spots.isEmpty) _spots = _suggestSpots();
      if (!drop) _spots = [];
      _mode = drop ? _Mode.spots : _Mode.edit;
    });
  }

  void _setColourMode(ColourMode mode) {
    setState(() {
      _push();
      _colourMode = mode;
      _colonies = _classified(_colonies, mode);
      _mode = mode == ColourMode.none ? _Mode.edit : _Mode.colour;
    });
  }

  Future<void> _editSpot(int i) async {
    // A Spot to keep, 'delete' to remove it, or null when dismissed.
    final result = await showDialog<Object>(
      context: context,
      builder: (context) => _SpotDialog(
        spot: _spots[i],
        index: i,
        count: countInSpot(_spots[i], _colonies),
        mmPerPx: _plate?.mmPerPx ?? 0.05,
      ),
    );
    if (!mounted || result == null || result == _spots[i]) return;
    setState(() {
      _push();
      final next = [..._spots];
      if (result is Spot) {
        next[i] = result;
      } else {
        next.removeAt(i);
      }
      _spots = next;
    });
  }

  // --- editing -------------------------------------------------------------

  /// Image pixels → screen pixels at the current zoom.
  double get _screenScale => _fitScale * _viewer.value.getMaxScaleOnAxis();
  double _fitScale = 1;

  int? _hit(Offset p) {
    final minHit = 16 / _screenScale; // at least ~16 screen px
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < _colonies.length; i++) {
      final c = _colonies[i];
      final d = (Offset(c.x, c.y) - p).distance;
      if (d <= math.max(c.radiusPx * 1.3, minHit) && d < bestD) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }

  double get _typicalRadius {
    final r = [
      for (final c in _colonies)
        if (!c.manual && c.n == 1) c.radiusPx,
    ]..sort();
    if (r.isEmpty) return 0.5 / (_plate?.mmPerPx ?? 0.05);
    return r[r.length ~/ 2];
  }

  bool _insidePlate(Offset p) {
    final pl = _plate;
    if (pl == null) return false;
    return pl.contains(p.dx, p.dy, rimFraction: kRimFraction);
  }

  void _push() {
    _undo.add((_colonies, _spots, _rejected, _excluded));
    _dirty = true;
  }

  /// Taps that would change marks nobody can see do nothing; say why.
  bool _editingHidden() {
    if (_showMarks || _mode == _Mode.zoom || _mode == _Mode.plate) return false;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr.reviewHintMarksHidden)));
    return true;
  }

  void _onTap(Offset p) {
    if (_editingHidden()) return;
    if (_mode == _Mode.spots) {
      final i = _hitSpot(p);
      if (i != null) {
        _editSpot(i);
      } else if (_insidePlate(p)) {
        setState(() {
          _push();
          _spots = [
            ..._spots,
            _labelSpot(Spot(p.dx, p.dy, _dropRadiusPx), _spots.length),
          ];
        });
      }
      return;
    }
    if (_mode == _Mode.squares) {
      final grid = _filmGrid, plate = _plate;
      if (grid == null || plate == null) return;
      final sq = squareAt(grid, p.dx, p.dy);
      if (!completeSquares(grid, plate).contains(sq)) return;
      setState(() {
        _push();
        _excluded = _excluded.contains(sq)
            ? ({..._excluded}..remove(sq))
            : {..._excluded, sq};
      });
      return;
    }
    if (_mode == _Mode.colour || _mode == _Mode.gas || _mode == _Mode.yellow) {
      final i = _hit(p);
      if (i == null) return;
      final c = _colonies[i];
      setState(() {
        _push();
        _colonies = [..._colonies]
          ..[i] = switch (_mode) {
            _Mode.gas => c.withGas(!c.gas),
            _Mode.yellow => c.withYellow(!c.yellow),
            _ => c.withCls(1 - c.cls),
          };
      });
      return;
    }
    if (_mode != _Mode.edit) return;
    final i = _hit(p);
    setState(() {
      if (i != null) {
        _push();
        if (!_colonies[i].manual) _rejected = [..._rejected, _colonies[i]];
        _colonies = [..._colonies]..removeAt(i);
      } else if (_insidePlate(p)) {
        _push();
        _colonies = [
          ..._colonies,
          Colony(p.dx, p.dy, _typicalRadius, manual: true),
        ];
      }
    });
  }

  Future<void> _onLongPress(Offset p) async {
    if (_mode != _Mode.edit || _editingHidden()) return;
    final i = _hit(p);
    if (i == null) return;
    final n = await showDialog<int>(
      context: context,
      builder: (context) => _ClusterDialog(initial: _colonies[i].n),
    );
    if (n == null || n == _colonies[i].n) return;
    setState(() {
      _push();
      _colonies = [..._colonies]..[i] = _colonies[i].withN(n);
    });
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      final (colonies, spots, rejected, excluded) = _undo.removeLast();
      _excluded = excluded;
      _colonies = colonies;
      _spots = spots;
      _rejected = rejected;
    });
  }

  void _panStart(Offset p) {
    if (_mode != _Mode.spots || !_showMarks) return;
    _dragSpot = _hitSpot(p);
    _dragAllSpots = _dragSpot == null && _spots.isNotEmpty;
    if (_dragSpot != null || _dragAllSpots) _push();
  }

  void _panUpdate(Offset delta) {
    if (_mode == _Mode.plate) return _movePlate(delta);
    if (_dragAllSpots) {
      setState(
        () => _spots = [
          for (final s in _spots)
            s.copyWith(cx: s.cx + delta.dx, cy: s.cy + delta.dy),
        ],
      );
      return;
    }
    final i = _dragSpot;
    if (i == null) return;
    setState(() {
      final s = _spots[i];
      _spots = [..._spots]
        ..[i] = s.copyWith(cx: s.cx + delta.dx, cy: s.cy + delta.dy);
    });
  }

  void _movePlate(Offset delta) {
    final pl = _plate;
    if (pl == null) return;
    setState(
      () => _plate = pl.copyWith(cx: pl.cx + delta.dx, cy: pl.cy + delta.dy),
    );
  }

  Future<void> _applyPlate() async {
    if (!await _confirmDiscardEdits()) return;
    await _recount(plate: _plate);
    if (mounted) setState(() => _mode = _Mode.edit);
  }

  Future<void> _adjustSensitivity() async {
    final value = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (context) => _SensitivitySheet(initial: _kSigma),
    );
    if (value == null || value == _kSigma) return;
    if (!await _confirmDiscardEdits()) return;
    _kSigma = value;
    await _recount(plate: _plate);
  }

  Future<void> _save() async {
    final plate = _plate;
    if (plate == null) return;
    final existing = widget.record;
    final base = widget.laterPhotoOf;
    final draft = PlateRecord(
      id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: existing?.createdAt ?? DateTime.now(),
      imagePath: existing?.imagePath ?? '',
      imageWidth: _imageW,
      imageHeight: _imageH,
      plate: plate,
      colonies: _colonies,
      autoCount: _autoCount,
      flags: _flags,
      sampleId:
          existing?.sampleId ??
          base?.sampleId ??
          widget.preset?.info.sampleId ??
          '',
      dilutionExp:
          existing?.dilutionExp ??
          base?.dilutionExp ??
          widget.preset?.slot.dilutionExp ??
          0,
      // A plate switched between a dish and a dry film takes the new type's
      // volume (films are 1 mL), not the one saved with the old type.
      volumeMl:
          _sameKind(existing)?.volumeMl ??
          _sameKind(base)?.volumeMl ??
          (widget.preset?.info.isFilm == _film
              ? widget.preset?.info.unitVolumeMl
              : null) ??
          (_drop
              ? 0.01
              : _format.membrane
              ? 100
              : _film
              ? 1
              : widget.store.defaultVolumeMl),
      notes: existing?.notes ?? '',
      spreader: existing?.spreader ?? _flags.contains('spreader'),
      // A film estimated from grid squares is counted, not "too many".
      tntc:
          existing?.tntc ??
          (_flags.contains('tntc') && !(_film && _filmTally.estimates != null)),
      guided: existing?.guided ?? widget.guided,
      kSigma: _kSigma,
      replicate:
          existing?.replicate ??
          base?.replicate ??
          widget.preset?.slot.replicate ??
          1,
      spots: _drop ? _spots : const [],
      colourMode: _colourMode,
      format: _format,
      rejected: _rejected,
      verified: existing?.verified ?? _accuracyCheckDue,
      seriesId:
          existing?.seriesId ??
          (base == null
              ? ''
              : (base.seriesId.isEmpty ? base.id : base.seriesId)),
      incubationH: existing?.incubationH ?? _suggestedHours(base),
      filmGrid: _film ? _filmGrid : null,
      excludedSquares: _film ? _excluded.toList() : const [],
    );
    final result = await showModalBottomSheet<PlateRecord>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SaveSheet(
        store: widget.store,
        draft: draft,
        fixedSample: widget.preset != null || base != null,
      ),
    );
    if (result == null) return;
    var record = result;
    if (existing == null) {
      final name = await widget.store.savePhoto(_photo!, record.id);
      record = PlateRecord.fromJson({...record.toJson(), 'image': name});
    }
    if (base != null && base.seriesId.isEmpty) {
      // The first photo starts the time-lapse series.
      await widget.store.upsert(base.copyWith(seriesId: base.id));
    }
    await widget.store.upsert(record);
    _dirty = false;
    if (mounted) Navigator.of(context).pop(record);
  }

  /// Centre of the [k]-th complete grid square, in image pixels (tests).
  @visibleForTesting
  Offset debugSquareCentre(int k) {
    final pts = squareOutline(
      _filmGrid!,
      completeSquares(_filmGrid!, _plate!)[k],
    );
    return Offset(
      pts.map((p) => p.$1).reduce((a, b) => a + b) / 4,
      pts.map((p) => p.$2).reduce((a, b) => a + b) / 4,
    );
  }

  /// Complete grid squares to draw over a film, when they matter: while
  /// an estimate is used or squares are being chosen.
  List<(List<(double, double)>, bool)> _squaresToDraw() {
    final grid = _filmGrid, plate = _plate;
    if (!_film || grid == null || plate == null || !_gridOk) return const [];
    if (_mode != _Mode.squares && _filmTally.estimates == null) {
      return const [];
    }
    return [
      for (final sq in completeSquares(grid, plate))
        (squareOutline(grid, sq), !_excluded.contains(sq)),
    ];
  }

  /// [r] when it is the same kind of plate (film or not) as the one being
  /// saved, else null.
  PlateRecord? _sameKind(PlateRecord? r) =>
      r != null && r.isFilm == _film ? r : null;

  /// [p] with radius [r]. A film's scale comes from its printed grid, so its
  /// diameter in mm follows the radius; a dish keeps its nominal size.
  Plate _resized(Plate p, double r) {
    final grid = _filmGrid;
    // A grid that was not found gives no scale either: keep the nominal size.
    if (!_film || grid == null || grid.strength < kGridMinStrength) {
      return p.copyWith(radius: r);
    }
    return Plate(p.cx, p.cy, r, diameterMm: 2 * r * grid.mmPerPx);
  }

  /// Hours since plating for a later photo: the earlier photo's hours plus
  /// the time between the two photos.
  double? _suggestedHours(PlateRecord? base) {
    final h = base?.incubationH;
    if (base == null || h == null) return null;
    final dt = DateTime.now().difference(base.createdAt).inMinutes / 60;
    return ((h + dt) * 2).round() / 2;
  }

  /// A new photo is due a colony-by-colony check for accuracy tracking.
  bool get _accuracyCheckDue {
    final every = widget.store.accuracyCheckEvery;
    if (widget.record != null || every <= 0) return false;
    var since = 0;
    for (final r in widget.store.records) {
      if (r.verified) break;
      since++;
    }
    return since >= every - 1;
  }

  void _openTimelapse() {
    // The series id is set on the first photo once a later one is saved.
    final id = widget.store.records
        .firstWhere(
          (r) => r.id == widget.record!.id,
          orElse: () => widget.record!,
        )
        .seriesId;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TimelapseScreen(store: widget.store, seriesId: id),
      ),
    );
  }

  Future<void> _chooseFormat() async {
    final f = await showDialog<PlateFormat>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr.reviewPlateType),
        children: [
          for (final f in PlateFormat.values)
            ListTile(
              leading: Icon(
                f == _format
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(f.text),
              onTap: () => Navigator.pop(context, f),
            ),
        ],
      ),
    );
    if (f == null || f == _format || !mounted) return;
    if (!await _confirmDiscardEdits()) return;
    _format = f;
    _filmGrid = null;
    if (f.isFilm) {
      _drop = false;
      _colourMode = ColourMode.none;
    }
    await _recount();
  }

  /// The drop table and CFU/mL for the banner, in ASCII: three dilutions
  /// to a line ("1e-5: 12 15 9 (mean 12.0) | 1e-6: 1 2 0 (mean 1.0)").
  List<String> _dropBannerLines() {
    if (_spots.isEmpty) return const [];
    final plan = _dropPlan;
    final mode = plan?.dropMode ?? DropMode.pooled;
    final window = plan?.dropWindow ?? kDropWindow;
    final rows = dilutionTable(dropCountsFromSpots(_spots, _colonies));
    final e = estimateDrops(
      rows,
      plan?.dropVolumeUl ?? (widget.record?.volumeMl ?? 0.01) * 1000,
      mode: mode,
      window: window,
    );
    final cells = [
      for (final r in rows)
        '1e-${r.dilutionExp}: ${[...r.counts.map((c) => '$c'), for (var i = 0; i < r.tntc; i++) 'TNTC'].join(' ')}'
            '${r.counts.isEmpty ? '' : ' (mean ${fixed(r.mean, 1)})'}',
    ];
    final q = switch (e.qualifier) {
      'exact' => '',
      '<' => '< ',
      '>' => '> ',
      _ => 'est. ',
    };
    return [
      for (var i = 0; i < cells.length; i += 3)
        cells.sublist(i, math.min(i + 3, cells.length)).join(' | '),
      if (e.cfuPerMl.isFinite)
        '$q${sciValue(e.cfuPerMl)} CFU/mL, '
            '${mode == DropMode.first ? 'first countable' : 'pooled'} '
            '${window.$1}-${window.$2}'
            '${e.dilutionsUsed.isEmpty ? '' : ' from ${e.dilutionsUsed.map((d) => '1e-$d').join(', ')}'}',
    ];
  }

  /// Banner lines for the annotated photo: what the plate is and its count.
  ///
  /// Stays in English on purpose: the banner is drawn onto the JPEG with an
  /// ASCII-only bitmap font, which cannot render Thai.
  List<String> _annotationHeader() {
    final en = lookupAppLocalizations(const Locale('en'));
    String dilution(int exp) => exp == 0 ? en.neat : dilutionLabel(exp);
    String flag(String f) => switch (f) {
      'spreader' => en.flagSpreader,
      'tntc' => en.flagTntc,
      'clusters_estimated' => en.flagClusters,
      'crowded' => en.flagCrowded,
      'many_clusters' => en.flagManyClusters,
      'low_contrast' => en.flagLowContrast,
      'grid_not_found' => en.flagGridNotFound,
      'estimated' => en.flagEstimated,
      'area_size_unexpected' => en.flagAreaSize,
      'colonies_outside_drops' => en.flagOutsideDrops,
      'layout_uncertain' => en.flagLayoutUncertain,
      _ => f,
    };
    final r = widget.record;
    final info = widget.preset?.info;
    final sample = r?.sampleId ?? info?.sampleId ?? '';
    final what = _drop
        ? 'drop plate (${_spots.length} drops)'
        : [
            dilution(r?.dilutionExp ?? widget.preset?.slot.dilutionExp ?? 0),
            'R${r?.replicate ?? widget.preset?.slot.replicate ?? 1}',
          ].join(' · ');
    final classes = _colourMode == ColourMode.none
        ? ''
        : ' (${[for (var k = 0; k < 2; k++) '${_colourMode.classNames[k]} ${_colonies.where((c) => c.cls == k).fold(0, (s, c) => s + c.n)}'].join(', ')})';
    var count = 'Count: $_count$classes';
    if (_film && _plate != null) {
      // English names for the ASCII banner font.
      const names = {
        'aerobic': 'Aerobic count',
        'ecoli': 'E. coli',
        'coliform': 'Coliforms',
        'enterobacteriaceae': 'Enterobacteriaceae',
        'yeast': 'Yeasts',
        'mold': 'Molds',
      };
      final t = _filmTally;
      count = [
        for (final k in kFilmTypes[_filmType]!.results)
          t.estimates?[k] == null
              ? '${names[k]} ${t.counts[k]}'
              : '${names[k]} est. ${t.estimates![k]!.round()}',
      ].join(' / ');
    }
    if (r != null && !_drop && !_film && r.volumeMl > 0) {
      count += ' · ${sciValue(_count / (r.volumeMl * r.dilution))} CFU/mL';
    }
    // Films whose rules use gas: every kind with and without it.
    final gas = _film && _plate != null && filmUsesGas(_filmType)
        ? [
            for (final MapEntry(key: kind, value: (g, n)) in gasSplit(
              _filmType,
              filmColoniesOf(_filmType, _colonies),
            ).entries)
              '${kind[0].toUpperCase()}${kind.substring(1)} $g with gas, $n without',
          ].join(' / ')
        : '';
    return [
      '${sample.isEmpty ? 'Unlabelled' : sample} · $what',
      count,
      if (gas.isNotEmpty) gas,
      if (_drop) ..._dropBannerLines(),
      [
        shortDate(r?.createdAt ?? DateTime.now()),
        if (_flags.isNotEmpty) _flags.map(flag).join(', '),
      ].join(' · '),
    ];
  }

  Future<void> _shareAnnotated() async {
    final photo = _photo, plate = _plate;
    if (photo == null || plate == null) return;
    setState(() => _busy = true);
    try {
      final jpeg = await compute(
        annotatePhoto,
        AnnotationJob(
          photo: photo,
          plate: plate,
          colonies: _colonies,
          spots: _drop ? _spots : const [],
          colourMode: _colourMode,
          header: _annotationHeader(),
        ),
      );
      final id = widget.record?.sampleId ?? widget.preset?.info.sampleId ?? '';
      final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      await shareBytes(
        jpeg,
        'plate_${safe.isEmpty ? 'count' : safe}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        'image/jpeg',
        subject: tr.reviewShareSubject,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr.reviewCouldNotShare('$e'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr.reviewDiscardTitle),
            content: Text(tr.reviewDiscardBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.reviewKeep),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr.reviewDiscard),
              ),
            ],
          ),
        );
        if ((leave ?? false) && context.mounted) {
          _dirty = false;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          // Room for the full title beside three actions on a 360 dp phone.
          titleSpacing: 0,
          title: Text(tr.reviewTitle),
          actions: [
            IconButton(
              tooltip: tr.reviewUndo,
              onPressed: _undo.isEmpty ? null : _undoLast,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: tr.reviewSensitivity,
              onPressed: _busy || _plate == null || _photo == null || _film
                  ? null
                  : _adjustSensitivity,
              icon: const Icon(Icons.tune),
            ),
            PopupMenuButton<Object>(
              enabled: _plate != null,
              tooltip: tr.reviewMenuTooltip,
              onSelected: (v) => v is ColourMode
                  ? _setColourMode(v)
                  : v == 'share'
                  ? _shareAnnotated()
                  : v == 'format'
                  ? _chooseFormat()
                  : v == 'later'
                  ? countNewPlate(
                      context,
                      widget.store,
                      laterPhotoOf: widget.record,
                    )
                  : v == 'timelapse'
                  ? _openTimelapse()
                  : v == 'find_drops'
                  ? _findDropsAgain()
                  : v == 'turn_labels'
                  ? _turnLabels()
                  : _setDrop(!_drop),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'share',
                  enabled: _photo != null && !_busy,
                  child: ListTile(
                    leading: const Icon(Icons.share),
                    title: Text(tr.reviewShareAnnotated),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (widget.record != null) ...[
                  PopupMenuItem(
                    value: 'later',
                    child: ListTile(
                      leading: const Icon(Icons.add_a_photo_outlined),
                      title: Text(tr.reviewAddLaterPhoto),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (widget.record!.seriesId.isNotEmpty)
                    PopupMenuItem(
                      value: 'timelapse',
                      child: ListTile(
                        leading: const Icon(Icons.timeline),
                        title: Text(tr.reviewTimelapse),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'format',
                  enabled: !_busy && _photo != null,
                  child: Text(tr.reviewPlateTypeItem(_format.text)),
                ),
                if (!_film) ...[
                  CheckedPopupMenuItem(
                    value: 'drop',
                    checked: _drop,
                    child: Text(tr.reviewDropPlate),
                  ),
                  if (_drop) ...[
                    PopupMenuItem(
                      value: 'find_drops',
                      enabled: !_busy && _photo != null,
                      child: Text(tr.reviewFindDrops),
                    ),
                    if (_spots.where((s) => s.position != null).length > 1 &&
                        _dropTemplate is SectorTemplate)
                      PopupMenuItem(
                        value: 'turn_labels',
                        child: Text(tr.reviewTurnLabels),
                      ),
                  ],
                  const PopupMenuDivider(),
                  for (final m in ColourMode.values)
                    CheckedPopupMenuItem(
                      value: m,
                      checked: _colourMode == m,
                      child: Text(tr.reviewColoursItem(m.text)),
                    ),
                ],
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _buildImage()),
            if (_plate != null) _buildPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (_error != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)),
      );
    }
    final photo = _photo;
    if (_imageW == 0 || photo == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(tr.reviewCounting),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        _fitScale = math.min(box.maxWidth / _imageW, box.maxHeight / _imageH);
        final plateMode = _mode == _Mode.plate;
        // Dragging moves the plate circle or a drop instead of the view.
        final lockView = plateMode || _mode == _Mode.spots;
        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: InteractiveViewer(
                  transformationController: _viewer,
                  maxScale: 12,
                  panEnabled: !lockView,
                  scaleEnabled: !lockView,
                  onInteractionUpdate: (_) =>
                      setState(() {}), // keep stroke widths crisp
                  child: Center(
                    child: FittedBox(
                      child: SizedBox(
                        width: _imageW.toDouble(),
                        height: _imageH.toDouble(),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => _onTap(d.localPosition),
                          onLongPressStart: (d) =>
                              _onLongPress(d.localPosition),
                          onPanStart: lockView
                              ? (d) => _panStart(d.localPosition)
                              : null,
                          onPanUpdate: lockView
                              ? (d) => _panUpdate(d.delta)
                              : null,
                          onPanEnd: lockView
                              ? (_) {
                                  _dragSpot = null;
                                  _dragAllSpots = false;
                                }
                              : null,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                photo,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                              ),
                              CustomPaint(
                                painter: _OverlayPainter(
                                  plate: _plate,
                                  colonies: _colonies,
                                  scale: _screenScale,
                                  plateMode: plateMode,
                                  spots: _drop ? _spots : const [],
                                  colourMode: _colourMode,
                                  showMarks: _showMarks,
                                  film: _film ? _filmType : null,
                                  filmCounted: _film ? _filmCounted : const [],
                                  squares: _squaresToDraw(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_plate != null)
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filledTonal(
                  tooltip: _showMarks ? tr.reviewHideMarks : tr.reviewShowMarks,
                  isSelected: !_showMarks,
                  onPressed: () => setState(() => _showMarks = !_showMarks),
                  icon: const Icon(Icons.visibility_outlined),
                  selectedIcon: const Icon(Icons.visibility_off_outlined),
                ),
              ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPanel() {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final edits = [
      if (_added > 0) tr.reviewAdded(_added),
      if (_removed > 0) tr.reviewRemoved(_removed),
      if (_removed < 0) tr.reviewInClusters(-_removed),
    ];
    final modes = [
      (_Mode.zoom, Icons.zoom_in, tr.reviewModeZoom),
      (_Mode.edit, Icons.touch_app, tr.reviewModeEdit),
      (_Mode.plate, Icons.radio_button_unchecked, tr.reviewModePlate),
      if (_drop) (_Mode.spots, Icons.bubble_chart_outlined, tr.reviewModeDrops),
      if (_colourMode != ColourMode.none && !_film)
        (_Mode.colour, Icons.palette_outlined, tr.reviewModeColour),
      if (_filmKindMode)
        (_Mode.colour, Icons.palette_outlined, tr.reviewModeKind),
      if (_filmGasMode)
        (_Mode.gas, Icons.bubble_chart_outlined, tr.reviewModeGas),
      if (_filmYellowMode) (_Mode.yellow, Icons.blur_on, tr.reviewModeYellow),
      if (_gridOk && _filmAboveRange)
        (_Mode.squares, Icons.grid_on, tr.reviewModeSquares),
    ];
    if (!modes.any((m) => m.$1 == _mode)) _mode = _Mode.edit;
    final compact = modes.length > 3;
    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Details scroll on short phones; the Save / Recount actions below
            // always stay visible.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$_count',
                          style: t.displaySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            _film ? tr.reviewFilmMarks(_count) : 'CFU',
                            style: t.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              edits.isEmpty
                                  ? tr.reviewAutomatic
                                  : tr.reviewAutoEdits(
                                      _autoCount,
                                      edits.join(' · '),
                                    ),
                              style: t.bodySmall,
                              textAlign: TextAlign.end,
                              maxLines: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    ..._banners(t, cs),
                    if (_film) ..._filmSummary(t, cs),
                    if (_colourMode != ColourMode.none && !_film)
                      _classSummary(t),
                    if (_drop) _dropSummary(t),
                    if (_flags.any(_showFlag))
                      Wrap(
                        spacing: 6,
                        children: [
                          // The estimate has its own banner.
                          for (final f in _flags)
                            if (_showFlag(f))
                              Chip(
                                label: Text(flagLabel(f)),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: f == 'clusters_estimated'
                                    ? null
                                    : cs.errorContainer,
                              ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    SegmentedButton<_Mode>(
                      showSelectedIcon: !compact,
                      segments: [
                        for (final (mode, icon, label) in modes)
                          ButtonSegment(
                            value: mode,
                            icon: compact ? null : Icon(icon),
                            label: Text(label),
                          ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) =>
                          setState(() => _mode = s.first),
                    ),
                    const SizedBox(height: 6),
                    Text(switch (_mode) {
                      _Mode.edit ||
                      _Mode.spots ||
                      _Mode.gas ||
                      _Mode.yellow ||
                      _Mode.colour when !_showMarks => tr.reviewHintMarksHidden,
                      _Mode.zoom => tr.reviewHintZoom,
                      _Mode.edit => tr.reviewHintEdit,
                      _Mode.plate =>
                        _plate?.isSquare ?? false
                            ? tr.reviewHintSquare
                            : tr.reviewHintCircle,
                      _Mode.spots => tr.reviewHintDropsLayout,
                      _Mode.colour when _film => tr.reviewHintKind(
                        filmKindText(filmKinds(_filmType)[0]).toLowerCase(),
                        filmKindText(filmKinds(_filmType).last).toLowerCase(),
                      ),
                      _Mode.colour => tr.reviewHintColour,
                      _Mode.gas => tr.reviewHintGas,
                      _Mode.yellow => tr.reviewHintYellow,
                      _Mode.squares => tr.reviewHintSquares,
                    }, style: t.bodySmall),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_mode == _Mode.plate && _plate != null) ...[
                    Slider(
                      label: tr.reviewSize,
                      value: _plate!.radius.clamp(
                        _imageW * 0.15,
                        _imageW * 0.7,
                      ),
                      min: _imageW * 0.15,
                      max: _imageW * 0.7,
                      onChanged: (v) =>
                          setState(() => _plate = _resized(_plate!, v)),
                    ),
                    if (_plate!.isSquare)
                      Row(
                        children: [
                          const Icon(Icons.rotate_right, size: 20),
                          Expanded(
                            child: Slider(
                              value: _plate!.angle.clamp(-0.8, 0.8),
                              min: -0.8,
                              max: 0.8,
                              onChanged: (v) => setState(
                                () => _plate = _plate!.copyWith(angle: v),
                              ),
                            ),
                          ),
                        ],
                      ),
                    FilledButton.tonalIcon(
                      onPressed: _busy || _photo == null ? null : _applyPlate,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        _plate!.isSquare
                            ? tr.reviewRecountSquare
                            : tr.reviewRecountCircle,
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: FilledButton.icon(
                        onPressed: _busy || _plate == null || _photo == null
                            ? null
                            : _save,
                        icon: const Icon(Icons.check),
                        label: Text(
                          widget.record == null
                              ? tr.reviewSavePlate
                              : tr.reviewSaveChanges,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Flag chips: a film estimated from grid squares has its own banner and
  /// is counted, so neither "estimated" nor "too many to count" applies.
  bool _showFlag(String f) =>
      f != 'estimated' &&
      f != 'grid_not_found' && // has its own banner
      !(f == 'tntc' && _film && _plate != null && _filmTally.estimates != null);

  Widget _banner(TextTheme t, IconData icon, Color bg, Color fg, String text) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: t.bodySmall?.copyWith(color: fg)),
            ),
          ],
        ),
      );

  /// "Check this count" when the automatic count is likely to be wrong, and
  /// the periodic accuracy check.
  List<Widget> _banners(TextTheme t, ColorScheme cs) {
    final warnings = [
      for (final f in _flags)
        // A film without a grid has its own banner (see _filmSummary).
        if (kCheckFlags.contains(f) && f != 'tntc' && f != 'grid_not_found')
          flagLabel(f).toLowerCase(),
    ];
    Widget banner(IconData icon, Color bg, Color fg, String text) =>
        _banner(t, icon, bg, fg, text);
    return [
      if (warnings.isNotEmpty && !_hasEdits)
        banner(
          Icons.warning_amber_rounded,
          cs.tertiaryContainer,
          cs.onTertiaryContainer,
          tr.reviewCheckCount(warnings.join(', ')),
        ),
      if (_accuracyCheckDue)
        banner(
          Icons.fact_check_outlined,
          cs.secondaryContainer,
          cs.onSecondaryContainer,
          tr.reviewAccuracyCheck,
        ),
    ];
  }

  /// Dry films: each result (with its estimate above the counting range),
  /// what was left out, and how an estimate was made.
  List<Widget> _filmSummary(TextTheme t, ColorScheme cs) {
    final type = _filmType;
    final tally = _filmTally;
    final ft = kFilmTypes[type]!;
    final cols = filmColoniesOf(type, _colonies);
    final notCounted = [
      for (final c in cols)
        if (!ft.results.any((k) => filmRule(type, k, c))) c,
    ].fold(0, (s, c) => s + c.n);
    final above = tally.counts.values.any((v) => v > ft.countMax);
    final est = tally.estimates;
    return [
      if (_flags.contains('grid_not_found'))
        _banner(
          t,
          Icons.grid_off,
          cs.errorContainer,
          cs.onErrorContainer,
          tr.reviewFilmNoGrid,
        ),
      if (est != null)
        _banner(
          t,
          Icons.grid_on,
          cs.secondaryContainer,
          cs.onSecondaryContainer,
          _excluded.isEmpty
              ? tr.reviewFilmEstimate(tally.squaresUsed)
              : '${tr.reviewFilmEstimate(tally.squaresUsed)} '
                    '${tr.reviewFilmSquaresLeftOut(_excluded.length)}',
        )
      else if (above && _filmGrid != null)
        _banner(
          t,
          Icons.grid_off,
          cs.tertiaryContainer,
          cs.onTertiaryContainer,
          tr.reviewFilmFewSquares,
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Wrap(
          spacing: 14,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final k in ft.results)
              Text(
                est?[k] == null
                    ? '${filmResultText(k)} ${tally.counts[k]}'
                    : '${filmResultText(k)} ≈ ${formatCount(est![k]!)} '
                          '(${tally.counts[k]})',
                style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            if (notCounted > 0)
              Text(
                type == 'ec'
                    ? tr.reviewFilmRedNoGas(notCounted)
                    : tr.reviewFilmNotCounted(notCounted),
                style: t.bodySmall,
              ),
          ],
        ),
      ),
      // Every kind with and without gas, counted or not (EC, CC, EB).
      if (filmUsesGas(type))
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            [
              for (final MapEntry(key: kind, value: (g, n)) in gasSplit(
                type,
                cols,
              ).entries)
                tr.reviewFilmGasSplit(filmKindText(kind), g, n),
            ].join(' · '),
            style: t.bodyMedium,
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(tr.reviewFilmAid, style: t.bodySmall),
      ),
    ];
  }

  Widget _classSummary(TextTheme t) {
    final counts = List.filled(_colourMode.classNames.length, 0);
    for (final c in _colonies) {
      counts[c.cls.clamp(0, counts.length - 1)] += c.n;
    }
    final total = counts.fold(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var k = 0; k < counts.length; k++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ClassDot(colour: _classColour(_colourMode, k)),
                const SizedBox(width: 4),
                Text(
                  tr.reviewClassCount(_colourMode.className(k), counts[k]),
                  style: t.bodyMedium,
                ),
              ],
            ),
          if (total > 0)
            Text(
              tr.reviewClassPercent(
                (counts[1] / total * 100).toStringAsFixed(1),
                _colourMode.className(1).toLowerCase(),
              ),
              style: t.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _dropSummary(TextTheme t) {
    if (_spots.isEmpty) {
      return Text(tr.reviewNoDrops, style: t.bodySmall);
    }
    final plan = _dropPlan;
    final volumeUl =
        plan?.dropVolumeUl ?? (widget.record?.volumeMl ?? 0.01) * 1000;
    final mode = plan?.dropMode ?? DropMode.pooled;
    final window = plan?.dropWindow ?? kDropWindow;
    final rows = dilutionTable(dropCountsFromSpots(_spots, _colonies));
    final chips = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (var i = 0; i < _spots.length; i++)
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: _spots[i].flags.isEmpty || _spots[i].isExcluded
                  ? null
                  : const Icon(Icons.warning_amber_rounded, size: 16),
              label: Text(
                '${i + 1}: ${dilutionLabel(_spots[i].dilutionExp)} R${_spots[i].replicate} · '
                '${_spots[i].tntc ? 'TNTC' : countInSpot(_spots[i], _colonies)}'
                '${_spots[i].isExcluded ? ' · ${tr.reviewDropLeftOut}' : ''}',
                style: _spots[i].isExcluded
                    ? const TextStyle(decoration: TextDecoration.lineThrough)
                    : null,
              ),
              onPressed: () => _editSpot(i),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chips,
        if (rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: DropTableView(
              rows: rows,
              estimate: estimateDrops(
                rows,
                volumeUl,
                mode: mode,
                window: window,
              ),
              mode: mode,
              window: window,
            ),
          ),
      ],
    );
  }
}

/// Mark colour for a film's kind: green for red colonies, yeasts and AC
/// (red marks would vanish on the red gel), light blue for blue colonies,
/// purple for molds.
Color _filmKindColour(String type, int cls) => switch ((type, cls)) {
  ('ym', 1) => Colors.purpleAccent,
  ('ac', _) || (_, 0) => Colors.greenAccent,
  _ => const Color(0xFF40C4FF),
};

Color _classColour(ColourMode mode, int cls) => switch ((mode, cls)) {
  (ColourMode.blueWhite, 1) => const Color(0xFF40C4FF),
  (ColourMode.twoColours, 1) => const Color(0xFFFF4081),
  _ => Colors.greenAccent,
};

class _ClassDot extends StatelessWidget {
  const _ClassDot({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: colour, width: 2.5),
    ),
  );
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.plate,
    required this.colonies,
    required this.scale,
    required this.plateMode,
    required this.spots,
    required this.colourMode,
    this.showMarks = true,
    this.film,
    this.filmCounted = const [],
    this.squares = const [],
  });

  /// Off: only the plate outline while moving it, nothing else.
  final bool showMarks;

  /// Dry-film type, when the plate is a film: marks are drawn by kind, with
  /// rings for gas and yellow zones; marks counted towards no result are
  /// faint ([filmCounted]).
  final String? film;
  final List<bool> filmCounted;

  /// Complete grid squares (corners in image pixels), and whether each is
  /// used by the estimate (false: left out by the user).
  final List<(List<(double, double)>, bool)> squares;
  final List<Spot> spots;
  final ColourMode colourMode;
  final Plate? plate;
  final List<Colony> colonies;

  /// Image pixels to screen pixels, so strokes stay ~2 px on screen at any zoom.
  final double scale;
  final bool plateMode;

  @override
  void paint(Canvas canvas, Size size) {
    final px = 1 / scale;
    final pl = plate;
    if (pl != null && (showMarks || plateMode)) {
      void outline(double rim, Paint paint) {
        if (!pl.isSquare) {
          canvas.drawCircle(Offset(pl.cx, pl.cy), pl.radius * rim, paint);
          return;
        }
        final pts = pl.outline(rimFraction: rim);
        canvas.drawPath(
          Path()..addPolygon([for (final (x, y) in pts) Offset(x, y)], true),
          paint,
        );
      }

      outline(
        kRimFraction,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (plateMode ? 3 : 1.5) * px
          ..color = plateMode
              ? Colors.amberAccent
              : Colors.cyanAccent.withValues(alpha: 0.8),
      );
      if (plateMode) {
        outline(
          1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 * px
            ..color = Colors.amberAccent.withValues(alpha: 0.5),
        );
      }
    }
    if (!showMarks) return;
    if (film != null) {
      _paintFilm(canvas, px);
      // On top of the marks: on crowded films they cover the gel.
      for (final (sq, used) in squares) {
        final pts = [for (final (x, y) in sq) Offset(x, y)];
        final path = Path()..addPolygon(pts, true);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (used ? 5 : 3) * px
            ..color = Colors.black54,
        );
        final line = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (used ? 2.5 : 1.5) * px
          ..color = used
              ? Colors.amberAccent
              : Colors.white.withValues(alpha: 0.7);
        canvas.drawPath(path, line);
        if (!used) {
          // Left out of the estimate: crossed through.
          canvas.drawLine(pts[0], pts[2], line);
          canvas.drawLine(pts[1], pts[3], line);
        }
      }
      return;
    }
    for (var i = 0; i < spots.length; i++) {
      final sp = spots[i];
      // Left out: grey and crossed through; confluent: red; crowded: orange.
      final colour = sp.isExcluded
          ? Colors.grey
          : sp.tntc
          ? Colors.redAccent
          : sp.flags.isNotEmpty
          ? Colors.orangeAccent
          : Colors.amberAccent;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * px
        ..color = colour;
      canvas.drawCircle(Offset(sp.cx, sp.cy), sp.radius, ring);
      if (sp.isExcluded) {
        final d = sp.radius * math.sqrt1_2;
        canvas.drawLine(
          Offset(sp.cx - d, sp.cy - d),
          Offset(sp.cx + d, sp.cy + d),
          ring,
        );
        canvas.drawLine(
          Offset(sp.cx - d, sp.cy + d),
          Offset(sp.cx + d, sp.cy - d),
          ring,
        );
      }
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1} · ${sp.tntc ? 'TNTC' : countInSpot(sp, colonies)}',
          style: TextStyle(
            color: Colors.black,
            backgroundColor: colour,
            fontSize: 13 * px,
            fontFamily: 'Roboto',
            fontFamilyFallback: const ['ColonySymbols'],
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(
          sp.cx - label.width / 2,
          sp.cy - sp.radius - label.height - 2 * px,
        ),
      );
    }
    final auto = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * px
      ..color = Colors.greenAccent;
    final class1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * px
      ..color = _classColour(colourMode, 1);
    final manual = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * px
      ..color = Colors.pinkAccent;
    final cluster = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * px
      ..color = Colors.orangeAccent;
    for (final c in colonies) {
      final r = math.max(c.radiusPx * 1.25, 5 * px);
      final paint = c.n > 1
          ? cluster
          : (c.manual
                ? manual
                : (colourMode != ColourMode.none && c.cls == 1
                      ? class1
                      : auto));
      canvas.drawCircle(Offset(c.x, c.y), r, paint);
      if (c.n > 1) {
        final tp = TextPainter(
          text: TextSpan(
            text: '×${c.n}',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontSize: 13 * px,
              fontFamily: 'Roboto',
              fontFamilyFallback: const ['ColonySymbols'],
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(c.x + r, c.y - tp.height / 2));
      }
    }
  }

  void _paintFilm(Canvas canvas, double px) {
    for (var i = 0; i < colonies.length; i++) {
      final c = colonies[i];
      final counted = i < filmCounted.length ? filmCounted[i] : true;
      final r = math.max(c.radiusPx * 1.25, 5 * px);
      final colour = c.n > 1
          ? Colors.orangeAccent
          : c.manual
          ? Colors.pinkAccent
          : _filmKindColour(film!, c.cls);
      canvas.drawCircle(
        Offset(c.x, c.y),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (counted ? 2.5 : 1.5) * px
          ..color = counted ? colour : colour.withValues(alpha: 0.45),
      );
      if (c.gas) {
        canvas.drawCircle(
          Offset(c.x, c.y),
          r + 3 * px,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 * px
            ..color = Colors.white,
        );
      }
      if (c.yellow) {
        canvas.drawCircle(
          Offset(c.x, c.y),
          r + (c.gas ? 6 : 3) * px,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 * px
            ..color = Colors.yellowAccent,
        );
      }
      if (c.n > 1) {
        final tp = TextPainter(
          text: TextSpan(
            text: '×${c.n}',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontSize: 13 * px,
              fontFamily: 'Roboto',
              fontFamilyFallback: const ['ColonySymbols'],
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(c.x + r, c.y - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.plate != plate ||
      old.colonies != colonies ||
      old.scale != scale ||
      old.plateMode != plateMode ||
      old.spots != spots ||
      old.colourMode != colourMode ||
      old.showMarks != showMarks ||
      old.film != film ||
      old.squares != squares;
}

class _ClusterDialog extends StatefulWidget {
  const _ClusterDialog({required this.initial});

  final int initial;

  @override
  State<_ClusterDialog> createState() => _ClusterDialogState();
}

class _ClusterDialogState extends State<_ClusterDialog> {
  late int _n = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr.reviewClusterTitle),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.outlined(
            onPressed: _n > 1 ? () => setState(() => _n--) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '$_n',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          IconButton.outlined(
            onPressed: _n < 50 ? () => setState(() => _n++) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr.reviewCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _n),
          child: Text(tr.reviewSet),
        ),
      ],
    );
  }
}

class _SensitivitySheet extends StatefulWidget {
  const _SensitivitySheet({required this.initial});

  final double initial;

  @override
  State<_SensitivitySheet> createState() => _SensitivitySheetState();
}

class _SensitivitySheetState extends State<_SensitivitySheet> {
  // The slider shows sensitivity; the detector threshold k·σ runs the other way.
  late double _k = widget.initial;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: scrollPadding(context, const EdgeInsets.fromLTRB(16, 0, 16, 24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr.reviewSensitivity, style: t.titleMedium),
          const SizedBox(height: 4),
          Text(tr.reviewSensitivityHelp, style: t.bodySmall),
          Row(
            children: [
              Text(tr.reviewLow),
              Expanded(
                child: Slider(
                  value: 10.5 - _k,
                  min: 2.5,
                  max: 8,
                  divisions: 11,
                  label: (10.5 - _k).toStringAsFixed(1),
                  onChanged: (v) => setState(() => _k = 10.5 - v),
                ),
              ),
              Text(tr.reviewHigh),
            ],
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _k),
            child: Text(tr.reviewRecount),
          ),
        ],
      ),
    );
  }
}

class _SpotDialog extends StatefulWidget {
  const _SpotDialog({
    required this.spot,
    required this.index,
    required this.count,
    required this.mmPerPx,
  });

  final Spot spot;
  final int index;
  final int count;
  final double mmPerPx;

  @override
  State<_SpotDialog> createState() => _SpotDialogState();
}

class _SpotDialogState extends State<_SpotDialog> {
  late Spot _s = widget.spot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final diameterMm = _s.radius * 2 * widget.mmPerPx;
    return AlertDialog(
      title: Text(tr.reviewDropTitle(widget.index + 1, widget.count)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: _s.dilutionExp,
                      decoration: InputDecoration(
                        labelText: tr.reviewDilution,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (var e = 0; e <= 10; e++)
                          DropdownMenuItem(
                            value: e,
                            child: Text(dilutionLabel(e)),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _s = _s.copyWith(dilutionExp: v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: _s.replicate,
                      decoration: InputDecoration(
                        labelText: tr.reviewReplicate,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (var r = 1; r <= 12; r++)
                          DropdownMenuItem(value: r, child: Text('R$r')),
                      ],
                      onChanged: (v) =>
                          setState(() => _s = _s.copyWith(replicate: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr.reviewTntc),
                subtitle: Text(tr.reviewConfluent),
                value: _s.tntc,
                onChanged: (v) => setState(() => _s = _s.copyWith(tntc: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr.reviewLeaveOut),
                subtitle: Text(tr.reviewLeaveOutHelp),
                value: _s.isExcluded,
                onChanged: (v) => setState(
                  () => _s = v
                      ? _s.copyWith(excluded: DropExclusion.splash)
                      : _s.copyWith(include: true),
                ),
              ),
              if (_s.isExcluded) ...[
                const SizedBox(height: 4),
                DropdownButtonFormField<DropExclusion>(
                  isExpanded: true,
                  initialValue: _s.excluded,
                  decoration: InputDecoration(
                    labelText: tr.reviewLeaveOutWhy,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final e in DropExclusion.values)
                      DropdownMenuItem(value: e, child: Text(e.text)),
                  ],
                  onChanged: (v) =>
                      setState(() => _s = _s.copyWith(excluded: v)),
                ),
                const SizedBox(height: 8),
              ],
              for (final f in _s.flags)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          f == 'crowded'
                              ? tr.reviewDropCrowded
                              : f == 'unplanned'
                              ? tr.reviewDropUnplanned
                              : f,
                          style: t.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                tr.reviewDropSize(diameterMm.toStringAsFixed(1)),
                style: t.bodySmall,
              ),
              Slider(
                value: diameterMm.clamp(2, 20),
                min: 2,
                max: 20,
                onChanged: (v) => setState(
                  () => _s = _s.copyWith(radius: v / 2 / widget.mmPerPx),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'delete'),
          child: Text(tr.reviewDeleteDrop),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr.reviewCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _s),
          child: Text(tr.reviewOk),
        ),
      ],
    );
  }
}
