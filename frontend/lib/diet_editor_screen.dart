part of 'main.dart';

// --- NUEVA PANTALLA: EDITOR DE DIETAS ---
class DietEditorScreen extends StatefulWidget {
  final Map<String, dynamic> diet;
  final String currentUserEmail;

  const DietEditorScreen({
    super.key,
    required this.diet,
    required this.currentUserEmail,
  });

  @override
  State<DietEditorScreen> createState() => _DietEditorScreenState();
}

class _DietEditorScreenState extends State<DietEditorScreen> {
  late TextEditingController _nameController;
  late int _selectedDay;
  List<Map<String, dynamic>> _meals = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.diet['name']);
    _selectedDay =
        int.tryParse(widget.diet['day_of_week']?.toString() ?? '1') ?? 1;
    _meals = List<Map<String, dynamic>>.from(widget.diet['meals'] ?? []);
  }

  InputDecoration _inputDecoration(String label) {
    final isLight = healthyTIsLightMode(context);
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: healthyTSecondaryText(context)),
      filled: true,
      fillColor: isLight
          ? const Color(0xFF111315).withOpacity(0.05)
          : Colors.white.withOpacity(0.06),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: healthyTGlassBorder(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: healthyTPrimaryText(context)),
      ),
    );
  }

  Widget _buildGlassContainer({
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
    double borderRadius = 24,
  }) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  healthyTGlassBase(
                    context,
                  ).withOpacity(healthyTIsLightMode(context) ? 0.64 : 0.72),
                  healthyTGlassBase(
                    context,
                  ).withOpacity(healthyTIsLightMode(context) ? 0.30 : 0.44),
                ],
              ),
              border: Border.all(color: healthyTGlassBorder(context)),
            ),
            child: IconTheme(
              data: IconThemeData(color: healthyTPrimaryText(context)),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: healthyTPrimaryText(context)),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveDietChanges() async {
    setState(() => _isLoading = true);
    await _persistDiet();
    setState(() => _isLoading = false);
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dieta guardada')));
  }

  void _editMeal(Map<String, dynamic> meal, int index) {
    TextEditingController nameC = TextEditingController(text: meal['name']);
    TextEditingController calC = TextEditingController(
      text: meal['calories']?.toString() ?? '0',
    );
    TextEditingController proC = TextEditingController(
      text: meal['protein']?.toString() ?? '0',
    );
    TextEditingController carbC = TextEditingController(
      text: meal['carbs']?.toString() ?? '0',
    );
    TextEditingController fatC = TextEditingController(
      text: meal['fats']?.toString() ?? '0',
    );
    TextEditingController notesC = TextEditingController(
      text: meal['notes']?.toString() ?? '',
    );
    final isLight = healthyTIsLightMode(context);
    final primaryText = healthyTPrimaryText(context);
    final dialogBackground = isLight
        ? const Color(0xFFF1F4F6)
        : const Color(0xFF1E1E1E);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBackground,
        title: Text('Editar Comida', style: TextStyle(color: primaryText)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                style: TextStyle(color: primaryText),
                decoration: _inputDecoration('Alimento'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: calC,
                style: TextStyle(color: primaryText),
                decoration: _inputDecoration('Calorías'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: proC,
                style: TextStyle(color: primaryText),
                decoration: _inputDecoration('Proteína (g)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: carbC,
                style: TextStyle(color: primaryText),
                decoration: _inputDecoration('Hidratos / carbohidratos (g)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: fatC,
                style: TextStyle(color: primaryText),
                decoration: _inputDecoration('Grasas (g)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesC,
                style: TextStyle(color: primaryText),
                decoration: _inputDecoration(
                  'Opciones y alimentos (A, B, C...)',
                ),
                minLines: 5,
                maxLines: 12,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final mealId = meal['id'];
              if (mealId != null) {
                try {
                  await Supabase.instance.client
                      .from('meals')
                      .delete()
                      .eq('id', mealId);
                } catch (e) {}
              }
              setState(() => _meals.removeAt(index));
              await _persistDiet();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text(
              'ELIMINAR',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final mealId = meal['id'];
              final updatedData = {
                'name': nameC.text,
                'calories': parseWholeNumber(calC.text),
                'protein': parseWholeNumber(proC.text),
                'carbs': parseWholeNumber(carbC.text),
                'fats': parseWholeNumber(fatC.text),
                'notes': notesC.text,
              };

              if (mealId != null) {
                try {
                  await Supabase.instance.client
                      .from('meals')
                      .update(updatedData)
                      .eq('id', mealId);
                } catch (e) {}
              }
              setState(() {
                _meals[index] = {...meal, ...updatedData};
              });
              await _persistDiet();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text(
              'GUARDAR',
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addMeal() async {
    Map<String, dynamic> newMeal = {
      'id': 'local_meal_${DateTime.now().millisecondsSinceEpoch}',
      'diet_id': widget.diet['id'],
      'name': 'Nuevo alimento',
      'calories': 0,
      'protein': 0,
      'carbs': 0,
      'fats': 0,
      'notes':
          '[OPCION A]\n• Categoría: \n  Alimento: \n  Cantidad: \n  Unidad: \n  Notas: ',
      'order_index': _meals.length,
      'local_only': true,
    };

    try {
      newMeal = await Supabase.instance.client
          .from('meals')
          .insert({
            'diet_id': widget.diet['id'],
            'name': 'Nuevo alimento',
            'calories': 0,
            'protein': 0,
            'carbs': 0,
            'fats': 0,
            'notes':
                '[OPCION A]\n• Categoría: \n  Alimento: \n  Cantidad: \n  Unidad: \n  Notas: ',
          })
          .select()
          .single();
    } catch (e) {
      debugPrint('No se pudo crear comida en Supabase, se guardará local: $e');
    }

    setState(() => _meals.add(newMeal));
    await _persistDiet();
    _editMeal(newMeal, _meals.length - 1);
  }

  Future<void> _persistDiet() async {
    try {
      await Supabase.instance.client
          .from('diets')
          .update({'name': _nameController.text, 'day_of_week': _selectedDay})
          .eq('id', widget.diet['id']);
    } catch (e) {}

    final diets = await LocalUserDataStore.loadDiets(widget.currentUserEmail);
    final updatedDiet = {
      ...Map<String, dynamic>.from(widget.diet),
      'name': _nameController.text,
      'day_of_week': _selectedDay,
      'meals': _meals,
    };

    final updatedDiets = diets.map((diet) {
      if (diet['id'] != widget.diet['id']) {
        return diet;
      }
      return updatedDiet;
    }).toList();

    await LocalUserDataStore.saveDiets(widget.currentUserEmail, updatedDiets);
  }

  @override
  Widget build(BuildContext context) {
    final isLight = healthyTIsLightMode(context);
    final primaryText = healthyTPrimaryText(context);
    final secondaryText = healthyTSecondaryText(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Editor de Dieta',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_rounded, color: Colors.greenAccent),
            onPressed: _saveDietChanges,
            tooltip: 'Guardar dieta',
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: healthyTPageGradient(context),
              ),
            ),
          ),
          Positioned(
            top: -50,
            right: -20,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isLight
                    ? const Color(0xFFDCE4EB).withOpacity(0.58)
                    : Colors.white.withOpacity(0.025),
              ),
            ),
          ),
          Positioned(
            top: 140,
            left: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isLight
                    ? const Color(0xFFD4DEE7).withOpacity(0.42)
                    : Colors.white.withOpacity(0.02),
              ),
            ),
          ),
          _isLoading
              ? Center(child: CircularProgressIndicator(color: primaryText))
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        controller: _nameController,
                        style: TextStyle(color: primaryText),
                        decoration: _inputDecoration('Nombre de la dieta'),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        value: _selectedDay,
                        isExpanded: true,
                        dropdownColor: isLight
                            ? const Color(0xFFF1F4F6)
                            : const Color(0xFF1E1E1E),
                        style: TextStyle(color: primaryText),
                        decoration: _inputDecoration('Día de la semana'),
                        items:
                            [
                                  'Lunes',
                                  'Martes',
                                  'Miércoles',
                                  'Jueves',
                                  'Viernes',
                                  'Sábado',
                                  'Domingo',
                                ]
                                .asMap()
                                .entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key + 1,
                                    child: Text(e.value),
                                  ),
                                )
                                .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedDay = val ?? 1),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Comidas',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryText,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _addMeal,
                            icon: const Icon(
                              Icons.add_circle_outline_rounded,
                              color: Colors.greenAccent,
                            ),
                            label: const Text(
                              'Añadir',
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Divider(
                        color: isLight
                            ? const Color(0xFF111315).withOpacity(0.10)
                            : Colors.white12,
                      ),
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        proxyDecorator: (child, index, animation) {
                          return Material(
                            color: Colors.transparent,
                            child: child,
                          );
                        },
                        itemCount: _meals.length,
                        onReorder: (oldIndex, newIndex) async {
                          if (newIndex > oldIndex) {
                            newIndex -= 1;
                          }
                          final movedMeal = _meals.removeAt(oldIndex);
                          _meals.insert(newIndex, movedMeal);
                          setState(() {});
                          await _persistDiet();
                        },
                        itemBuilder: (context, index) {
                          final meal = _meals[index];
                          final notes = meal['notes']?.toString().trim() ?? '';
                          final macros =
                              '${meal['calories']} kcal | P: ${meal['protein']}g | H: ${meal['carbs']}g | G: ${meal['fats']}g';
                          final hasMacros =
                              (double.tryParse(
                                        meal['calories']?.toString() ?? '0',
                                      ) ??
                                      0) >
                                  0 ||
                              (double.tryParse(
                                        meal['protein']?.toString() ?? '0',
                                      ) ??
                                      0) >
                                  0 ||
                              (double.tryParse(
                                        meal['carbs']?.toString() ?? '0',
                                      ) ??
                                      0) >
                                  0 ||
                              (double.tryParse(
                                        meal['fats']?.toString() ?? '0',
                                      ) ??
                                      0) >
                                  0;

                          return KeyedSubtree(
                            key: ValueKey(
                              meal['id']?.toString() ??
                                  '${meal['name'] ?? 'meal'}_$index',
                            ),
                            child: _buildGlassContainer(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              borderRadius: 22,
                              child: ListTile(
                                title: Text(
                                  meal['name'],
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: primaryText,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: _DietPreviewTextBlock(
                                    text: hasMacros
                                        ? (notes.isEmpty
                                              ? macros
                                              : '$notes\n\n$macros')
                                        : notes,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.edit_note_rounded,
                                      size: 23,
                                      color: secondaryText,
                                    ),
                                    const SizedBox(width: 10),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Icon(
                                        Icons.drag_handle_rounded,
                                        size: 25,
                                        color: secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () => _editMeal(meal, index),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}
