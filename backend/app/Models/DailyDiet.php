<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class DailyDiet extends Model
{
    public function up(): void
{
    Schema::create('daily_diets', function (Blueprint $table) {
        $table->id();
        $table->foreignId('user_id')->constrained()->cascadeOnDelete();
        $table->foreignId('food_id')->constrained();
        $table->float('grams'); // Cantidad consumida
        $table->date('consumed_at'); // Fecha del registro
        $table->timestamps();
    });
}
}
