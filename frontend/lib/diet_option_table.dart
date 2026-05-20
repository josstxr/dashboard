part of 'main.dart';

class _DietPreviewTextBlock extends StatelessWidget {
  final String text;

  const _DietPreviewTextBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    return _DietOptionTable(text: text, isExpanded: true);
  }
}

class _DietOptionPreviewRow {
  final String option;
  final String detail;

  const _DietOptionPreviewRow({required this.option, required this.detail});
}

class _DietOptionTable extends StatelessWidget {
  final String text;
  final bool isExpanded;
  final int collapsedRows;

  const _DietOptionTable({
    required this.text,
    required this.isExpanded,
    this.collapsedRows = 3,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = healthyTIsLightMode(context);
    final primaryText = healthyTPrimaryText(context);
    final secondaryText = healthyTSecondaryText(context);
    final borderColor = healthyTGlassBorder(context);
    final rows = _parseDietOptionRows(text);
    if (rows.isEmpty) {
      return Text(
        text,
        maxLines: isExpanded ? null : 6,
        overflow: isExpanded ? null : TextOverflow.ellipsis,
        style: TextStyle(
          color: isExpanded ? primaryText : secondaryText,
          fontSize: 12,
          height: 1.35,
        ),
      );
    }

    final visibleRows = isExpanded ? rows : rows.take(collapsedRows).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: isLight
              ? const Color(0xFF111315).withOpacity(0.04)
              : const Color(0xFF202326).withOpacity(0.56),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: [
            ...visibleRows.asMap().entries.map((entry) {
              final isLast = entry.key == visibleRows.length - 1;
              final row = entry.value;
              return IntrinsicHeight(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: isLast
                          ? BorderSide.none
                          : BorderSide(color: borderColor),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 92,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        color: isLight
                            ? const Color(0xFF111315).withOpacity(0.08)
                            : const Color(0xFF141618).withOpacity(0.72),
                        child: Text(
                          row.option.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: primaryText,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                      ),
                      Container(width: 1, color: borderColor),
                      Expanded(
                        child: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 9,
                          ),
                          color: isLight
                              ? const Color(0xFFF5F7F9).withOpacity(0.60)
                              : const Color(0xFF25282B).withOpacity(0.50),
                          child: Text(
                            row.detail,
                            maxLines: isExpanded ? null : 3,
                            overflow: isExpanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: TextStyle(
                              color: primaryText,
                              fontSize: 11.5,
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (!isExpanded && rows.length > visibleRows.length)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                color: isLight
                    ? const Color(0xFF111315).withOpacity(0.06)
                    : const Color(0xFF151719).withOpacity(0.58),
                child: Text(
                  'Ver opciones completas',
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_DietOptionPreviewRow> _parseDietOptionRows(String value) {
    final rows = <_DietOptionPreviewRow>[];
    final itemsByOption = <String, List<String>>{};
    final titleByOption = <String, String>{};
    final order = <String>[];
    String currentOption = '';
    String currentTitle = '';
    Map<String, String>? currentItem;

    void registerOption(String rawOption) {
      final parsed = _parseOptionLabel(rawOption);
      currentOption = parsed.$1;
      currentTitle = parsed.$2;
      if (currentOption.isEmpty) {
        currentOption = rawOption.trim();
      }
      if (!itemsByOption.containsKey(currentOption)) {
        itemsByOption[currentOption] = <String>[];
        order.add(currentOption);
      }
      if (currentTitle.isNotEmpty) {
        titleByOption[currentOption] = currentTitle;
      }
    }

    void flushItem() {
      if (currentItem == null) {
        return;
      }
      if (currentOption.isEmpty) {
        registerOption('OPCION');
      }

      final itemText = _formatDietItem(currentItem!);
      if (itemText.isNotEmpty) {
        itemsByOption[currentOption]!.add(itemText);
      }
      currentItem = null;
    }

    for (final rawLine in value.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final bracketOption = RegExp(r'^\[(.+)\]$').firstMatch(line);
      final plainOption = RegExp(
        r'^(OPCI[ÓO]N\s+[A-Z])(?:\s*\((.+)\))?$',
        caseSensitive: false,
      ).firstMatch(line);
      if (bracketOption != null || plainOption != null) {
        flushItem();
        registerOption(bracketOption?.group(1) ?? line);
        continue;
      }

      if (line.startsWith('• Categoría:')) {
        flushItem();
        currentItem = {
          'categoria': line.replaceFirst('• Categoría:', '').trim(),
        };
        continue;
      }

      currentItem ??= <String, String>{};
      if (line.startsWith('Alimento:')) {
        currentItem!['alimento'] = line.replaceFirst('Alimento:', '').trim();
      } else if (line.startsWith('Cantidad:')) {
        currentItem!['cantidad'] = line.replaceFirst('Cantidad:', '').trim();
      } else if (line.startsWith('Unidad:')) {
        currentItem!['unidad'] = line.replaceFirst('Unidad:', '').trim();
      } else if (line.startsWith('Notas:')) {
        currentItem!['notas'] = line.replaceFirst('Notas:', '').trim();
      } else {
        final previous = currentItem!['notas'] ?? '';
        currentItem!['notas'] = previous.isEmpty ? line : '$previous $line';
      }
    }
    flushItem();

    for (final option in order) {
      final title = titleByOption[option] ?? '';
      final items = itemsByOption[option] ?? const <String>[];
      final detailParts = [
        if (title.isNotEmpty) '${title.toUpperCase()}:',
        if (items.isNotEmpty) items.join(' / '),
      ];
      final detail = detailParts.join(' ').trim();
      if (detail.isNotEmpty) {
        rows.add(_DietOptionPreviewRow(option: option, detail: detail));
      }
    }

    return rows;
  }

  (String, String) _parseOptionLabel(String rawOption) {
    final option = rawOption.trim();
    final match = RegExp(
      r'^(OPCI[ÓO]N\s+[A-Z])(?:\s*\((.+)\))?',
      caseSensitive: false,
    ).firstMatch(option);
    if (match == null) {
      return (option, '');
    }
    return (
      match.group(1)?.toUpperCase().replaceAll('Ó', 'O') ?? option,
      match.group(2)?.trim() ?? '',
    );
  }

  String _formatDietItem(Map<String, String> item) {
    final amount = item['cantidad'] ?? '';
    final unit = item['unidad'] ?? '';
    final food = item['alimento'] ?? '';
    final notes = item['notas'] ?? '';
    final category = item['categoria'] ?? '';
    final main = [
      if (amount.isNotEmpty) amount,
      if (unit.isNotEmpty) unit,
      if (food.isNotEmpty) food,
    ].join(' ').trim();

    final parts = [
      if (main.isNotEmpty) main,
      if (notes.isNotEmpty) notes,
      if (main.isEmpty && notes.isEmpty && category.isNotEmpty) category,
    ];

    return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
