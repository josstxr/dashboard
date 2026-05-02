<?php
namespace App\Http\Controllers;
use Illuminate\Http\Request;
use App\Models\Workout;
use App\Models\Exercise;
use App\Imports\WorkoutsImport;
use Maatwebsite\Excel\Facades\Excel;
use Smalot\PdfParser\Parser;

class WorkoutController extends Controller
{
    public function index() {
        return response()->json(Workout::with('exercises')->get());
    }

    public function uploadFile(Request $request) {
        $request->validate(['file' => 'required|mimes:xlsx,xls,csv,pdf']);
        $file = $request->file('file');
        if ($file->getClientOriginalExtension() == 'pdf') {
            return $this->importFromPdf($file);
        }
        Excel::import(new WorkoutsImport, $file);
        return response()->json(['message' => 'Exito']);
    }

    private function importFromPdf($file) {
    try {
        $parser = new Parser();
        $pdf = $parser->parseFile($file->getPathname());
        $text = $pdf->getText();

        // 1. Buscamos todas las apariciones de "DIA X" o "DÍA X"
        preg_match_all('/D[IÍ]A\s+(\d+)/i', $text, $matches);
        $diasNumeros = $matches[1] ?? [];
        
        // 2. Dividimos el texto usando "DIA X" como separador
        $secciones = preg_split('/D[IÍ]A\s+\d+/i', $text, -1, PREG_SPLIT_NO_EMPTY);
        
        // Si el documento empieza con una introducción, la descartamos
        if (count($secciones) > count($diasNumeros)) {
            array_shift($secciones); 
        }

        foreach ($secciones as $index => $contenido) {
            $numeroDia = $diasNumeros[$index] ?? ($index + 1);
            $nombreRutina = "Día " . $numeroDia;

            // Creamos la rutina con su día asignado
            $workout = Workout::updateOrCreate(
                ['name' => $nombreRutina, 'user_id' => 1],
                ['day_of_week' => $numeroDia]
            );

            // 3. Procesamiento dinámico de los ejercicios
            // Convertimos todo a una sola línea porque el PDF puede separar un solo ejercicio en múltiples líneas
            $textoDia = preg_replace('/\s+/', ' ', trim($contenido));
            
            // Limpiamos los encabezados de tabla fragmentados
            $textoDia = str_ireplace('EJERCICIO SERIES DESCANS CARGA S REPS O NOTA', '', $textoDia);
            $textoDia = preg_replace('/EJERCICIO\s+SERIES\s+DESCANS/iu', '', $textoDia);
            $textoDia = preg_replace('/EJERCICIO\s+SERIES\s+REPS\s+DESCANS\s+NOTA/iu', '', $textoDia);
            
            // 1er Intento: Patrón para la estructura con etiquetas explícitas
            // Ejemplo: "EJERCICIO: KASS PRESS, SERIES: 3 DESCANSO: 3 min REPS: 8-10, CARGAS: Fallo, NOTA: PESADAS"
            $patternLabels = '/EJERCICIO:\s*(?P<name>.*?)\s*(?:,\s*)?SERIES:\s*(?P<sets>\d+)\s*(?:,\s*)?DESCANSO:\s*(?P<rest>\d+)\s*(?P<unit>[a-z]+)?\s*(?:,\s*)?REPS:\s*(?P<reps>.*?)\s*(?:,\s*)?CARGAS:\s*(?P<cargas>.*?)\s*(?:,\s*)?NOTA:\s*(?P<notes>.*?)(?=\s*EJERCICIO:|$)/isu';

            // Patrón global avanzado:
            // Busca: Nombre, [Series], Reps, [Descanso], Notas. Soporta que todo esté en una sola línea fluida.
            // Lookahead (?= ... | $) asegura que capture las notas hasta que comience el siguiente ejercicio.
            $pattern = '/(?P<name>[a-záéíóúñ][a-záéíóúñ\s\-\(\)\/]{2,80}?)\s+(?:(?P<sets>\d{1,2})\s+)?(?P<reps>\d+[\-\d]*)\s+(?:(?P<rest>\d+)\s*(?P<unit>MIN|M|S|SEG)?\s+)?(?P<notes>.*?)(?=(?:[a-záéíóúñ][a-záéíóúñ\s\-\(\)\/]{2,80}?)\s+(?:\d{1,2}\s+)?\d+[\-\d]*\s|$)/isu';

            if (preg_match_all($patternLabels, trim($textoDia), $matches, PREG_SET_ORDER) && count($matches) > 0) {
                foreach ($matches as $m) {
                    $name  = trim($m['name']);
                    $sets  = !empty($m['sets']) ? (int)$m['sets'] : 3;
                    $reps  = trim($m['reps']);
                    
                    $restVal = !empty($m['rest']) ? (int)$m['rest'] : 60;
                    $unit = strtoupper(trim($m['unit'] ?? ''));
                    $rest = ($unit === 'MIN' || $unit === 'M') ? $restVal * 60 : $restVal;
                    
                    $cargas = trim($m['cargas'] ?? '');
                    $notasRaw = trim($m['notes'] ?? '');
                    
                    // Concatenamos "CARGAS" y "NOTA" ya que en la BD solo tenemos la columna "notes"
                    $notes = '';
                    if (!empty($cargas)) $notes .= "Cargas: " . $cargas;
                    if (!empty($notasRaw)) $notes .= (!empty($notes) ? " | " : "") . "Nota: " . $notasRaw;
                    
                    $this->addExercise($workout->id, $name, $sets, $reps, $rest, $notes);
                }
            } elseif (preg_match_all($pattern, trim($textoDia), $matches, PREG_SET_ORDER) && count($matches) > 0) {
                foreach ($matches as $m) {
                    $name  = trim($m['name']);
                    $sets  = !empty($m['sets']) ? (int)$m['sets'] : 3;
                    $reps  = $m['reps'];
                    
                    $restVal = !empty($m['rest']) ? (int)$m['rest'] : 60;
                    $unit = strtoupper($m['unit'] ?? '');
                    $rest = ($unit === 'MIN' || $unit === 'M') ? $restVal * 60 : $restVal;
                    
                    $notes = trim($m['notes'] ?? '');
                    
                    $this->addExercise($workout->id, $name, $sets, $reps, $rest, $notes);
                }
            } else {
                // Fallback: Si la regex global no detecta nada, usamos el método original condensado
                $lineas = explode("\n", trim($contenido));
                foreach ($lineas as $linea) {
                    $linea = trim($linea);
                    if (strlen($linea) < 4) continue;
                    
                    if (preg_match('/^(.*?)\s+(?:(\d{1,2})\s+)?(\d+[\-\d]*)\s+(\d+)\s*(MIN|M|S|SEG)?\s*(.*)$/i', $linea, $m)) {
                        $rest = (strtoupper($m[5] ?? '') === 'MIN' || strtoupper($m[5] ?? '') === 'M') ? (int)$m[4] * 60 : (int)$m[4];
                        $this->addExercise($workout->id, trim($m[1]), !empty($m[2]) ? (int)$m[2] : 3, $m[3], $rest, trim($m[6] ?? ''));
                    } elseif (preg_match('/^(.*?)\s+(?:(\d{1,2})\s+)?(\d+[\-\d]*)\s+(.*)$/i', $linea, $m)) {
                        $this->addExercise($workout->id, trim($m[1]), !empty($m[2]) ? (int)$m[2] : 3, $m[3], 60, trim($m[4] ?? ''));
                    } else {
                        $this->addExercise($workout->id, $linea, 3, '10', 60, '');
                    }
                }
            }
        }
        return response()->json(['message' => 'Plan completo organizado']);
    } catch (\Exception $e) {
        return response()->json(['error' => $e->getMessage()], 500);
    }
}

    // --- NUEVOS MÉTODOS PARA EDITAR/ELIMINAR ---

    public function update(Request $request, $id) {
        $workout = Workout::findOrFail($id);
        // Permite actualizar el nombre de la rutina o cambiarla de día
        $workout->update($request->only(['name', 'day_of_week']));
        return response()->json(['message' => 'Rutina actualizada con éxito', 'workout' => $workout]);
    }

    public function destroy($id) {
        Workout::destroy($id);
        return response()->json(['message' => 'Rutina eliminada']);
    }

    public function updateExercise(Request $request, $id) {
        $exercise = Exercise::findOrFail($id);
        // Permite cambiar series, reps, descanso, nombre, etc.
        $exercise->update($request->all());
        return response()->json(['message' => 'Ejercicio actualizado', 'exercise' => $exercise]);
    }

    public function destroyExercise($id) {
        Exercise::destroy($id);
        return response()->json(['message' => 'Ejercicio eliminado']);
    }

private function addExercise($workoutId, $name, $sets, $reps, $rest, $notes) {
    Exercise::updateOrCreate(
        ['workout_id' => $workoutId, 'name' => $name],
        ['sets' => $sets, 'reps' => $reps, 'rest_seconds' => $rest, 'notes' => $notes]
    );
}
}