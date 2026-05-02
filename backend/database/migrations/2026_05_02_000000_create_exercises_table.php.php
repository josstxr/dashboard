<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
        public function up(): void
    {
        Schema::create('exercises', function (Blueprint $table) {
            $table->id();
            $table->foreignId('workout_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            
            // --- Campos en Inglés (usados por el PDF y el Seeder) ---
            $table->integer('sets')->nullable();
            $table->string('reps')->nullable(); // String porque a veces dice "8-10" o "Fallo"
            $table->integer('rest_seconds')->nullable();
            $table->text('notes')->nullable();
            
            // --- Campos en Español (usados por el importador de Excel) ---
            $table->integer('series')->nullable();
            $table->string('descanso')->nullable();
            $table->string('carga')->nullable();
            $table->text('notas')->nullable();
            
            $table->timestamps();
        });
    }


    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('exercises');
    }
};
