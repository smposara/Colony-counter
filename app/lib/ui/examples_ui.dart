import 'package:flutter/material.dart';

import '../data/examples.dart';
import '../data/plate_store.dart';
import '../l10n/l10n.dart';

/// A slim note above every tab while example data is here, with a way to
/// remove it.
class ExamplesBanner extends StatelessWidget {
  const ExamplesBanner({super.key, required this.store});

  final PlateStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!hasExamples(store)) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        return Material(
          key: const ValueKey('examplesBanner'),
          color: cs.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 18,
                  color: cs.onSecondaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr.examplesBanner,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.onSecondaryContainer),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => confirmRemoveExamples(context, store),
                  child: Text(tr.examplesRemove),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Marks an example plate, sample or zone plate in a list.
class ExampleBadge extends StatelessWidget {
  const ExampleBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tr.examplesBadge,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: cs.onSecondaryContainer),
      ),
    );
  }
}

/// [title] followed by an [ExampleBadge] when [example].
Widget titleWithBadge(Widget title, bool example) => example
    ? Row(
        children: [
          Flexible(child: title),
          const SizedBox(width: 8),
          const ExampleBadge(),
        ],
      )
    : title;

/// Asks, then removes the example data.
Future<void> confirmRemoveExamples(
  BuildContext context,
  PlateStore store,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr.examplesRemoveTitle),
      content: Text(tr.examplesRemoveBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr.homeCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(tr.examplesRemoveAction),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await removeExamples(store);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(tr.saveFailed('$e'))));
  }
}

/// Loads the example data again (Settings).
Future<void> addExampleData(BuildContext context, PlateStore store) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await addExamples(store);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(tr.saveFailed('$e'))));
  }
}
