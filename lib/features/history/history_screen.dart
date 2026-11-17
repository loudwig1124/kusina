/// History (`docs/07` §7 screen 9): completed and abandoned cooks with the stock
/// events they wrote, expandable read-only rows on the same screen.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scope.dart';
import '../../domain/guide/guide_models.dart';
import '../../domain/models/stock.dart';
import '../../ui/pixel/pixel_canvas.dart';
import '../../ui/pixel/pixel_chip.dart';
import '../../ui/pixel/pixel_panel.dart';
import '../../ui/pixel/pixel_scaffold.dart';
import '../../ui/pixel/pixel_theme.dart';
import 'history_controller.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _loaded = false;

  /// 0 = Sessions, 1 = Stock events (`docs/07` screen 9).
  int _segment = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _loaded) {
        return;
      }
      _loaded = true;
      await AppScope.of(context).history.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = AppScope.of(context).history;
    final unit = PixelScaleProvider.of(context).au(1);
    return ListenableBuilder(
      listenable: history,
      builder: (context, _) {
        final entries = history.entries;
        return PixelPage(
          title: 'HISTORY',
          onSettings: () => context.push('/settings'),
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: unit * 2,
                runSpacing: unit * 2,
                children: <Widget>[
                  PixelFilterChip(
                    label: 'Sessions',
                    selected: _segment == 0,
                    onTap: () => setState(() => _segment = 0),
                  ),
                  PixelFilterChip(
                    label: 'Stock events',
                    selected: _segment == 1,
                    onTap: () => setState(() => _segment = 1),
                  ),
                ],
              ),
              SizedBox(height: unit * 2),
              Text(
                _segment == 0
                    ? '${entries.length} '
                          '${entries.length == 1 ? 'COOK' : 'COOKS'}'
                    : '${history.events.length} '
                          '${history.events.length == 1 ? 'EVENT' : 'EVENTS'}',
                style: PixelType.chromeMeta,
              ),
              SizedBox(height: unit * 2),
            ],
          ),
          body: history.isLoading
              ? const Center(
                  child: Text('Loading history…', style: PixelType.meta),
                )
              : _segment == 1
              ? _EventsSegment(events: history.events)
              : entries.isEmpty
              ? Center(
                  child: PixelPanel(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('NO COOKS YET', style: PixelType.sectionLabel),
                        SizedBox(height: unit * 2),
                        Text(
                          'No cooks yet. Start with Cook now.',
                          style: PixelType.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.only(bottom: unit * 4),
                  itemCount: entries.length,
                  separatorBuilder: (context, index) =>
                      SizedBox(height: unit * 3),
                  itemBuilder: (context, index) => _HistoryRow(
                    entry: entries[index],
                    expanded: history.isExpanded(entries[index].session.id),
                    onToggle: () => history.toggle(entries[index].session.id),
                  ),
                ),
        );
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.expanded,
    required this.onToggle,
  });

  final HistorySession entry;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    final session = entry.session;
    final statusLabel = HistoryController.statusLabel(session.status);
    final isCompleted = session.status == SessionStatus.completed;
    return Semantics(
      button: true,
      expanded: expanded,
      label:
          '${session.recipeName}, $statusLabel, ${entry.events.length} '
          'stock changes',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: PixelPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(session.recipeName, style: PixelType.stepTitle),
                  ),
                  PixelFilterChip(
                    label: statusLabel,
                    selected: isCompleted,
                    onTap: onToggle,
                  ),
                ],
              ),
              SizedBox(height: unit),
              Text(
                session.isReview ||
                        session.currentStepNumber > session.totalSteps
                    ? 'All ${session.totalSteps} steps'
                    : 'Stopped at step ${session.currentStepNumber} of '
                          '${session.totalSteps}',
                style: PixelType.meta,
              ),
              SizedBox(height: unit),
              Text(
                expanded ? 'HIDE CHANGES (TAP)' : 'SHOW CHANGES (TAP)',
                style: PixelType.chromeMeta,
              ),
              if (expanded) ...<Widget>[
                SizedBox(height: unit * 2),
                Container(height: unit, color: PixelPalette.creamDark),
                SizedBox(height: unit * 2),
                if (entry.events.isEmpty)
                  Text(
                    isCompleted
                        ? 'No stock changes on this cook.'
                        : 'Abandoned cooks write no stock changes.',
                    style: PixelType.bodySmall,
                  )
                else
                  for (final event in entry.events)
                    Padding(
                      padding: EdgeInsets.only(bottom: unit),
                      child: Text(
                        '${event.ingredientCode.replaceAll('_', ' ')}: '
                        '${HistoryController.eventLine(event)}',
                        style: PixelType.rowLabel,
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Every stock event, including the unlinked review restock rows.
class _EventsSegment extends StatelessWidget {
  const _EventsSegment({required this.events});

  final List<StockEvent> events;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    if (events.isEmpty) {
      return Center(
        child: PixelPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('NO STOCK EVENTS YET', style: PixelType.sectionLabel),
              SizedBox(height: unit * 2),
              Text(
                'Finish a usage review and its stock changes appear here.',
                style: PixelType.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(bottom: unit * 4),
      itemCount: events.length,
      separatorBuilder: (context, index) => SizedBox(height: unit * 2),
      itemBuilder: (context, index) {
        final event = events[index];
        return PixelPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                HistoryController.ingredientLabel(event),
                style: PixelType.rowLabel.copyWith(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: unit),
              Text(
                HistoryController.eventLine(event),
                style: PixelType.bodySmall,
              ),
              SizedBox(height: unit),
              Text(HistoryController.linkLabel(event), style: PixelType.meta),
            ],
          ),
        );
      },
    );
  }
}
