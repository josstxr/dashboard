<?php

namespace App\Http\Controllers;

use App\Models\Food;
use App\Models\DailyDiet;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;

class DietController extends Controller
{
    public function identifyFood(Request $request)
    {
        $request->validate(['image' => 'required|string']);

        $apiKey = env('GEMINI_API_KEY');
        
        // URL oficial de Gemini 1.5 Flash
        $url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={$apiKey}";

        $response = Http::post($url, [
            "contents" => [
                [
                    "parts" => [
                        ["text" => "Analiza la imagen e identifica el alimento. Responde ÚNICAMENTE un objeto JSON con estas llaves: 'name' (nombre en español), 'calories', 'protein', 'carbs', 'fats' (por cada 100g) y 'estimated_grams' (peso visual en el plato)."],
                        [
                            "inline_data" => [
                                "mime_type" => "image/jpeg",
                                "data" => $request->image // El base64 que llega de Flutter
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig" => [
                "response_mime_type" => "application/json"
            ]
        ]);

        if ($response->failed()) {
            return response()->json(['error' => 'Error al conectar con Gemini'], 500);
        }

        // Extraer el texto de la respuesta de Gemini
        $resultText = $response->json()['candidates'][0]['content']['parts'][0]['text'];
        $data = json_decode($resultText, true);

        // Guardar en PostgreSQL
        $food = Food::firstOrCreate(
            ['name' => $data['name']],
            [
                'calories' => $data['calories'],
                'protein'  => $data['protein'],
                'carbs'    => $data['carbs'],
                'fats'     => $data['fats'],
            ]
        );

        DailyDiet::create([
            'user_id' => 1, 
            'food_id' => $food->id,
            'grams'   => $data['estimated_grams'],
            'consumed_at' => now()->format('Y-m-d'),
        ]);

        return response()->json([
            'message' => 'Alimento registrado con Gemini',
            'details' => $data
        ]);
    }
}