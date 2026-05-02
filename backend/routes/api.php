<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\WorkoutController;
use App\Http\Controllers\DietController; // Asegúrate de tener este controlador creado

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
*/
// Rutas de las rutinas
Route::get('/workouts', [WorkoutController::class, 'index']);
Route::post('/workouts/import', [WorkoutController::class, 'uploadFile']);

// Rutas nuevas para editar o cambiar el día de las Rutinas
Route::put('/workouts/{id}', [WorkoutController::class, 'update']);
Route::delete('/workouts/{id}', [WorkoutController::class, 'destroy']);

// Rutas nuevas para editar o eliminar Ejercicios individuales
Route::put('/exercises/{id}', [WorkoutController::class, 'updateExercise']);
Route::delete('/exercises/{id}', [WorkoutController::class, 'destroyExercise']);

// Rutas de Usuario
Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');

// Rutas de Entrenamiento (Healthy-T)
Route::get('/workouts', [WorkoutController::class, 'index']);

// CORRECCIÓN: El método debe ser uploadFile para manejar PDF y Excel
Route::post('/workouts/import', [WorkoutController::class, 'uploadFile']);

// Rutas de Dieta con IA (Gemini)
// Aplicamos el límite de 5 peticiones por minuto para cuidar tu cuota de API
Route::middleware('throttle:5,1')->group(function () {
    Route::post('/diet/identify', [DietController::class, 'identifyFood']);
});