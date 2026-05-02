<?php

namespace App\Imports;

use App\Models\Workout;
use App\Models\Exercise;
use Maatwebsite\Excel\Concerns\ToModel;
use Maatwebsite\Excel\Concerns\WithHeadingRow;

class WorkoutsImport implements ToModel, WithHeadingRow
{
    public function model(array $row)
    {
        // Buscamos o creamos la rutina (ej. "DIA 1 ARMS A")
        $workout = Workout::firstOrCreate([
            'name' => $row['workout_name'] ?? 'Nueva Rutina'
        ]);

        return new Exercise([
            'workout_id' => $workout->id,
            'name'       => $row['exercise_name'],
            'series'     => (int)$row['series'],
            'reps'       => $row['reps'],
            'descanso'   => $row['descanso'],
            'carga'      => $row['carga'], // Captura el RIR o FALLO[cite: 1]
            'notas'      => $row['notas'], // Captura el Tempo o variaciones[cite: 1]
        ]);
    }
}