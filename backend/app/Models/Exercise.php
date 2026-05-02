<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Exercise extends Model
{
    use HasFactory;

    // Agrega esta línea si no la tienes
    protected $fillable = [
        'workout_id', 
        'name', 
        'sets', 
        'reps', 
        'rest_seconds', 
        'notes',
        'series',    // De tu importador Excel
        'descanso',  // De tu importador Excel
        'carga',     // De tu importador Excel
        'notas'      // De tu importador Excel
    ];

    public function workout()
    {
        return $this->belongsTo(Workout::class);
    }
}
