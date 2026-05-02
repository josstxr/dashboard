<?php

namespace Database\Seeders;

use App\Models\User;
use App\Models\Workout;
use App\Models\Exercise;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        // 1. Creamos un usuario de prueba (necesario por la relación de las tablas)
        $user = User::factory()->create([
            'name' => 'Atleta',
            'email' => 'atleta@appgym.com',
        ]);

        // 2. Creamos una rutina de ejemplo
        $workout = Workout::create([
            'user_id' => $user->id,
            'name' => 'Día 1: Pecho y Tríceps',
            'day_of_week' => 1,
        ]);

        // 3. Le agregamos un par de ejercicios con el tiempo de descanso para tu cronómetro
        Exercise::create([
            'workout_id' => $workout->id,
            'name' => 'Press de Banca',
            'sets' => 4,
            'reps' => 10,
            'rest_seconds' => 90,
        ]);

        Exercise::create([
            'workout_id' => $workout->id,
            'name' => 'Extensiones de Tríceps',
            'sets' => 3,
            'reps' => 12,
            'rest_seconds' => 60,
        ]);
    }
}