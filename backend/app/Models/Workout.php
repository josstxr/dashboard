<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Workout extends Model
{
    use HasFactory;

    // Agrega esta línea para permitir la asignación masiva
    protected $fillable = ['name', 'user_id', 'day_of_week'];

    public function exercises()
    {
        return $this->hasMany(Exercise::class);
    }
}
