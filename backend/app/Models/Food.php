<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Food extends Model
{
    public function up(): void
{
    Schema::create('foods', function (Blueprint $table) {
        $table->id();
        $table->string('name');
        $table->float('calories');
        $table->float('protein');
        $table->float('carbs');
        $table->float('fats');
        $table->timestamps();
    });
}
}
